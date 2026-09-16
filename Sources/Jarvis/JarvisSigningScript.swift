import Foundation

/// 安装与签名脚本共用的 shell 片段。
///
/// 这套流程原本有三份各自演化的拷贝（`install.sh`、本机签名的 adoption 脚本、
/// 更新流程的 installer 脚本），改一处签名逻辑要在三个地方各改一遍，而它们做的是
/// 同一件安全敏感的事：给这台 Mac 生成证书、写信任设置、重新签名。片段因此收在
/// 这里，两份内嵌脚本直接引用。
///
/// `install.sh` 是个例外：它必须能单独通过 `curl | zsh` 跑起来，运行时引用不到
/// Swift 常量，所以内嵌同一段文本。`JarvisSigningScriptTests` 会断言两边逐字一致，
/// 让漂移在 CI 上就失败，而不是等用户升级后才发现权限没了。
///
/// 各片段只依赖这几个变量，调用方负责先设好：`identity`（证书 CN）、`work`
/// （可写临时目录）、`bundle_id`、`login_keychain`、`entitlements`、`target`。
enum JarvisSigningScript {
    /// 登录钥匙串路径。三种入口都在同一个用户的会话里，路径一致。
    static let loginKeychain = "$HOME/Library/Keychains/login.keychain-db"

    /// 证书不存在时生成一张并导入登录钥匙串。
    ///
    /// `-T` 把钥匙串条目的访问权授给 codesign 和 security，否则之后每次签名都会
    /// 弹一次钥匙串授权框。
    static let ensureIdentity = """
    if ! /usr/bin/security find-identity -p codesigning 2>/dev/null | /usr/bin/grep -qF "$identity"; then
        log "生成本机签名证书"
        /usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \\
            -keyout "$work/key.pem" -out "$work/cert.pem" \\
            -subj "/CN=$identity/O=Jarvis Local" \\
            -addext "basicConstraints=critical,CA:false" \\
            -addext "keyUsage=critical,digitalSignature" \\
            -addext "extendedKeyUsage=critical,codeSigning" || { log "生成证书失败"; exit 1; }
        /usr/bin/security import "$work/cert.pem" -k "$login_keychain" \\
            -T /usr/bin/codesign || { log "导入证书失败"; exit 1; }
        /usr/bin/security import "$work/key.pem" -k "$login_keychain" \\
            -T /usr/bin/codesign -T /usr/bin/security || { log "导入私钥失败"; exit 1; }
        /usr/bin/security find-identity -p codesigning | /usr/bin/grep -qF "$identity" \\
            || { log "证书导入后仍查不到"; exit 1; }
    fi
    """

    /// 把证书写进本机信任设置，让它成为一张完整的代码签名身份。
    ///
    /// 只影响这张密钥签出的代码，且仅对本用户生效：证书带 `CA:false`，当不了任何
    /// 东西的签发者。写信任设置这一步可能需要用户授权，失败时只记录、不中断——
    /// 不做这一步也能签出可用的应用，只是钥匙串会反复询问访问权限。
    static let trustIdentity = """
    if ! /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -qF "$identity"; then
        log "把证书加入信任设置"
        /usr/bin/security find-certificate -c "$identity" -p \\
            "$login_keychain" > "$work/identity.crt" || { log "导出证书失败"; exit 1; }
        /usr/bin/security add-trusted-cert -r trustRoot -p codeSign \\
            -k "$login_keychain" "$work/identity.crt" >/dev/null 2>&1 \\
            || log "写入信任设置失败，继续签名"
    fi
    """

    /// 清掉旧签名留下的 TCC 条目。
    ///
    /// 这些授权属于 ad-hoc 签名时的那个身份，重新签名后不会转移过去，留着只会在
    /// 「系统设置」里显示成一条指向已不存在应用的空授权。
    static let resetPrivacyPermissions = """
    /usr/bin/tccutil reset ScreenCapture "$bundle_id" >/dev/null 2>&1
    /usr/bin/tccutil reset Accessibility "$bundle_id" >/dev/null 2>&1
    """

    /// 用本机身份签名并校验。
    static let signAndVerify = """
    /usr/bin/codesign --force --options runtime --entitlements "$entitlements" \\
        --sign "$identity" "$target" || { log "签名失败"; exit 1; }
    /usr/bin/codesign --verify --deep --strict "$target" || { log "签名校验失败"; exit 1; }
    """

    /// 等父进程退出，超时后逐级升级信号。
    ///
    /// 只等不催的写法会在应用卡在退出流程时永远停住，把用户留在一个既没有旧应用
    /// 也没有新应用的中间态。
    static let waitForParentExit = """
    wait_ticks=0
    while /bin/kill -0 "$parent_pid" 2>/dev/null && (( wait_ticks < 150 )); do
        process_state=$(/bin/ps -p "$parent_pid" -o stat= 2>/dev/null || true)
        [[ "$process_state" == Z* ]] && break
        /bin/sleep 0.1
        (( wait_ticks += 1 ))
    done
    if /bin/kill -0 "$parent_pid" 2>/dev/null; then
        log "应用未在等待期内退出，发送 TERM"
        /bin/kill -TERM "$parent_pid" 2>/dev/null || true
        /bin/sleep 0.5
    fi
    if /bin/kill -0 "$parent_pid" 2>/dev/null; then
        log "应用仍未退出，发送 KILL"
        /bin/kill -KILL "$parent_pid" 2>/dev/null || true
    fi
    /bin/sleep 0.4
    """

    /// 去掉下载遗留的隔离标记。
    ///
    /// 发布包没有开发者 ID 签名，留着 quarantine 会被 Gatekeeper 挡住启动；只在
    /// 签名校验通过之后才摘，避免给一个来路不明的包放行。
    static let stripQuarantine = """
    if /usr/bin/xattr -p com.apple.quarantine "$target" >/dev/null 2>&1; then
        /usr/bin/xattr -dr com.apple.quarantine "$target" 2>&1 || log "移除 quarantine 失败"
    fi
    """

    /// 重新签名时使用的 entitlements。
    ///
    /// 与 `Resources/Jarvis.entitlements` 是同一份内容：重新签名会整体替换签名，
    /// 漏掉这里就等于静默收走麦克风和摄像头权限。`JarvisSigningScriptTests` 断言
    /// 两者一致。
    static let entitlements = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>com.apple.security.cs.allow-jit</key>
    \t<true/>
    \t<key>com.apple.security.device.audio-input</key>
    \t<true/>
    \t<key>com.apple.security.device.camera</key>
    \t<true/>
    </dict>
    </plist>
    """
}
