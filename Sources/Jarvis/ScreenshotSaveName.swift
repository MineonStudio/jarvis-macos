import Foundation

/// 保存面板里的默认文件名。
///
/// 只有时间戳（`20260918-123100.png`）。这个文件是用户自己的图，按日期找得到就够
/// 了；前面再挂个应用名，改名、排序、批量处理都得先把它剥掉。
///
/// 固定 `en_US_POSIX`：跟随系统区域的话，非公历地区（比如佛历）会得到一串意料之外
/// 的年份数字，文件名跟着乱。
enum ScreenshotSaveName {
    static func defaultName(at date: Date = Date(), timeZone: TimeZone = .current) -> String {
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
