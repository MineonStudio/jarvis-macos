import Foundation

/// 图片落盘时用的文件名：只有时间戳（`20260918-123100.png`）。
///
/// 三个出口共用这一套：保存面板的默认名、历史截图拖到 Finder 的落盘名、剪贴板里的
/// 图片拖出去的落盘名。这类文件是用户自己的图，按日期找得到就够了；前面挂应用名、
/// 或者干脆是一串内部 UUID，改名、排序、批量处理都得先把它剥掉。剪贴板里还有个
/// 「每张都叫 `图片.png`」的版本——拖第二张就撞名。
///
/// 区域固定 `en_US_POSIX`：跟随系统区域的话，非公历地区（比如佛历）会得到一串意料
/// 之外的年份数字，文件名跟着乱。
enum ScreenshotFileName {
    static func timestamped(at date: Date = Date(), timeZone: TimeZone = .current) -> String {
        "\(makeFormatter(timeZone: timeZone).string(from: date)).png"
    }

    /// 单独拿出来是为了能被测试检查配置：区域必须钉死。进程的当前区域在测试里换不掉，
    /// 只断言输出形状的话，把 `en_US_POSIX` 这行删掉测试也不会红。
    static func makeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }
}
