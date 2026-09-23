import AppKit
import SwiftUI

struct JarvisTaskPermissionOverlay: View {
    @Environment(AppModel.self) private var app
    let prompt: JarvisTaskPermissionPrompt

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.16))
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 18) {
                Image(systemName: prompt.permission.systemImage)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.jarvisAccent)
                    .frame(width: 108, height: 84)
                    .background(Color.jarvisAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))

                VStack(spacing: 8) {
                    Text(prompt.title)
                        .font(JarvisTypography.pageTitle)
                        .multilineTextAlignment(.center)
                    Text(prompt.message)
                        .font(JarvisTypography.secondary)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("获取权限") {
                        app.handleTaskPermissionPromptAction()
                    }
                    .buttonStyle(PermissionCapsuleButtonStyle(isPrimary: true))
                    .frame(maxWidth: .infinity)

                    Button("暂不") {
                        app.taskPermissionPrompt = nil
                    }
                    .buttonStyle(PermissionCapsuleButtonStyle(isPrimary: false))
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(28)
            .frame(width: 440)
            .jarvisGlass(cornerRadius: 24, interactive: false)
            .shadow(color: Color.black.opacity(0.16), radius: 32, y: 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt.title)
    }
}

private struct PermissionCapsuleButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTypography.bodyEmphasis)
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                Capsule(style: .continuous)
                    .fill(isPrimary ? Color.jarvisAccent : Color.jarvisInsetSurface)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isPrimary ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct JarvisPermissionGateOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.16))
                .ignoresSafeArea()
                .contentShape(Rectangle())

            JarvisPermissionGateView()
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
        }
        .onAppear {
            app.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissionStatus()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("先让我帮得上忙")
    }
}

struct JarvisPermissionGateView: View {
    @Environment(AppModel.self) private var app
    @State private var isAdoptingIdentity = false
    @State private var adoptionFailure: String?

    private var remainingCount: Int {
        JarvisRequiredPermission.allCases.count { !app.isRequiredPermissionGranted($0) }
    }

    private var invitationLine: String {
        switch remainingCount {
        case 0: "都好了，我们开始。"
        case 1: "就差这一步了。"
        default: "打开这些，我们就开始。"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            JarvisOrbMark(diameter: 58)

            VStack(spacing: 7) {
                Text("先让我帮得上忙")
                    .font(JarvisTypography.pageTitle)
                    .multilineTextAlignment(.center)
                Text(invitationLine)
                    .font(JarvisTypography.secondary)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .multilineTextAlignment(.center)
                Text("贾维斯需要这四项权限才能开始工作；屏幕录制和辅助功能授权后需要重启一次。")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .multilineTextAlignment(.center)
            }

            JarvisPermissionList()

            if JarvisLocalSigning.canAdoptLocalIdentity {
                signingAdoptionCard
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 26)
        .frame(width: 400)
        .jarvisGlass(cornerRadius: 24, interactive: false)
        .shadow(color: Color.black.opacity(0.16), radius: 32, y: 14)
        .onAppear {
            // 签名是在应用退出之后由脚本完成的，失败原因只能由下一次启动认领。
            if let reason = JarvisLocalSigning.consumeAdoptionFailure() {
                adoptionFailure = "上次签名失败：\(reason)"
            }
        }
    }

    /// Releases are ad-hoc signed, so an app dragged out of the download zip
    /// loses every grant on each update. Signing this copy with a certificate
    /// made on this Mac fixes that for good; the offer sits here because it
    /// costs one round of grants either way.
    private var signingAdoptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "signature")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.jarvisAccent)
                Text("让以后的更新不再重新授权")
                    .font(JarvisTypography.bodyEmphasis)
            }

            Text("贾维斯会在这台 Mac 上生成一张证书给自己签名，之后每次更新都沿用同一个身份，权限只授一次。证书不会离开这台 Mac。")
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("点下去贾维斯会自己关掉再重新打开，中途不用管它；万一失败也会自动开回来并在这里说明原因。")
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let adoptionFailure {
                Text(adoptionFailure)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                startAdoption()
            } label: {
                HStack(spacing: 6) {
                    if isAdoptingIdentity {
                        ProgressView().controlSize(.small)
                    }
                    Text(isAdoptingIdentity ? "正在签名…" : "签名并立即重启")
                }
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
            .disabled(isAdoptingIdentity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jarvisAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func startAdoption() {
        isAdoptingIdentity = true
        adoptionFailure = nil
        do {
            try JarvisLocalSigning.adoptLocalIdentity()
            // The detached script waits for this process to exit before it
            // swaps in the newly signed copy and opens it again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
        } catch {
            isAdoptingIdentity = false
            adoptionFailure = "签名失败：\(error.localizedDescription)"
        }
    }
}

enum JarvisPermissionListMode: Equatable {
    case gate
    case settings
}

/// The four required permissions with their current state. The gate cannot be
/// dismissed, so this is the only place grants are requested.
struct JarvisPermissionList: View {
    var cornerRadius: CGFloat = 16
    var mode: JarvisPermissionListMode = .gate

    var body: some View {
        if mode == .settings {
            HStack(spacing: 8) {
                ForEach(JarvisRequiredPermission.allCases) { permission in
                    JarvisPermissionStatusCapsule(permission: permission)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(JarvisRequiredPermission.allCases.enumerated()), id: \.element.id) { index, permission in
                    JarvisPermissionRow(permission: permission)
                    if index < JarvisRequiredPermission.allCases.count - 1 {
                        Divider()
                            .opacity(0.45)
                            .padding(.leading, 50)
                    }
                }
            }
            .background(
                Color.jarvisInsetSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

private struct JarvisPermissionStatusCapsule: View {
    @Environment(AppModel.self) private var app
    let permission: JarvisRequiredPermission

    var body: some View {
        let isGranted = app.isRequiredPermissionGranted(permission)
        return HStack(spacing: 7) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : permission.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isGranted ? Color.green : Color.jarvisTextSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(isGranted ? "已授权" : "未授权")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(isGranted ? Color.green : Color.jarvisTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isGranted ? Color.green.opacity(0.08) : Color.jarvisInsetSurface,
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    isGranted ? Color.green.opacity(0.2) : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(permission.title)，\(isGranted ? "已授权" : "未授权")")
        .animation(JarvisMotion.selection, value: isGranted)
    }
}

private struct JarvisPermissionRow: View {
    @Environment(AppModel.self) private var app
    let permission: JarvisRequiredPermission

    var body: some View {
        let isGranted = app.isRequiredPermissionGranted(permission)
        return HStack(spacing: 12) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isGranted ? Color.green : Color.jarvisAccent)
                .frame(width: 30, height: 30)
                .background(
                    (isGranted ? Color.green : Color.jarvisAccent).opacity(0.12),
                    in: Circle()
                )

            Text(permission.title)
                .font(JarvisTypography.bodyEmphasis)
                .foregroundStyle(isGranted ? Color.jarvisTextSecondary : Color.primary)

            Spacer(minLength: 8)

            if isGranted {
                Text("已就绪")
                    .font(JarvisTypography.captionEmphasis)
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(permission.title)已就绪")
            } else {
                Button("允许") {
                    app.requestRequiredPermission(permission)
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
                .controlSize(.small)
                .accessibilityLabel("允许\(permission.title)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .animation(JarvisMotion.selection, value: isGranted)
    }
}
