import AppKit
import Foundation
import ImageIO

enum WallpaperSource: String, CaseIterable, Codable, Hashable, Identifiable {
    case wallhaven
    /// Kept for decoding older local-library records. New wallpapers are sourced
    /// exclusively from Wallhaven.
    case local

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .wallhaven: "Wallhaven"
        case .local: "本地"
        }
    }

    var icon: String {
        switch self {
        case .wallhaven: "photo.on.rectangle.angled"
        case .local: "folder"
        }
    }
}

enum WallpaperResolution: String, CaseIterable, Codable, Hashable, Identifiable {
    case any
    case hd
    case fullHD
    case wuxga
    case uwfhd
    case qHD
    case uwqhd
    case uhd
    case fiveK
    case superUltrawide
    case eightK

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .any: "不限分辨率"
        case .hd: "720p 及以上"
        case .fullHD: "1080p 及以上"
        case .wuxga: "1920 × 1200 及以上"
        case .uwfhd: "2560 × 1080 及以上"
        case .qHD: "2K 及以上"
        case .uwqhd: "3440 × 1440 及以上"
        case .uhd: "4K 及以上"
        case .fiveK: "5K 及以上"
        case .superUltrawide: "5120 × 1440 及以上"
        case .eightK: "8K 及以上"
        }
    }

    var shortTitle: String {
        switch self {
        case .any: "不限"
        case .hd: "720p+"
        case .fullHD: "1080p"
        case .wuxga: "1920×1200"
        case .uwfhd: "2560×1080"
        case .qHD: "2K"
        case .uwqhd: "3440×1440"
        case .uhd: "4K"
        case .fiveK: "5K"
        case .superUltrawide: "5120×1440"
        case .eightK: "8K"
        }
    }

    var minimumResolution: String? {
        switch self {
        case .any: nil
        case .hd: "1280x720"
        case .fullHD: "1920x1080"
        case .wuxga: "1920x1200"
        case .uwfhd: "2560x1080"
        case .qHD: "2560x1440"
        case .uwqhd: "3440x1440"
        case .uhd: "3840x2160"
        case .fiveK: "5120x2880"
        case .superUltrawide: "5120x1440"
        case .eightK: "7680x4320"
        }
    }
}

enum WallpaperRatio: String, CaseIterable, Codable, Hashable, Identifiable {
    case any
    case landscape
    case portrait
    case square
    case sixteenByNine
    case sixteenByTen
    case twentyOneByNine
    case thirtyTwoByNine
    case nineBySixteen
    case tenBySixteen

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .any: "不限比例"
        case .landscape: "横屏"
        case .portrait: "竖屏"
        case .square: "方形"
        case .sixteenByNine: "16:9"
        case .sixteenByTen: "16:10"
        case .twentyOneByNine: "21:9"
        case .thirtyTwoByNine: "32:9"
        case .nineBySixteen: "9:16"
        case .tenBySixteen: "10:16"
        }
    }

    var apiValue: String? {
        switch self {
        case .any: nil
        case .landscape: "16x9,16x10,21x9,32x9"
        case .portrait: "9x16,10x16"
        case .square: "1x1"
        case .sixteenByNine: "16x9"
        case .sixteenByTen: "16x10"
        case .twentyOneByNine: "21x9"
        case .thirtyTwoByNine: "32x9"
        case .nineBySixteen: "9x16"
        case .tenBySixteen: "10x16"
        }
    }
}

enum WallpaperSorting: String, CaseIterable, Codable, Hashable, Identifiable {
    case toplist
    case dateAdded
    case relevance
    case views
    case favorites

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .toplist: "热门"
        case .dateAdded: "最新"
        case .relevance: "相关"
        case .views: "浏览量"
        case .favorites: "收藏数"
        }
    }

    var apiValue: String {
        switch self {
        case .toplist: "toplist"
        case .dateAdded: "date_added"
        case .relevance: "relevance"
        case .views: "views"
        case .favorites: "favorites"
        }
    }
}

enum WallpaperLibraryMode: String, CaseIterable, Identifiable {
    case online
    case downloaded
    case favorites

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .online: "在线图库"
        case .downloaded: "已下载"
        case .favorites: "我的收藏"
        }
    }
}

struct WallpaperTagSuggestion: Hashable, Identifiable {
    let title: String
    let query: String

    var id: String {
        query
    }
}

enum WallpaperTags {
    static let popular: [WallpaperTagSuggestion] = [
        WallpaperTagSuggestion(title: "风景", query: "landscape"),
        WallpaperTagSuggestion(title: "自然", query: "nature"),
        WallpaperTagSuggestion(title: "海洋", query: "ocean"),
        WallpaperTagSuggestion(title: "森林", query: "forest"),
        WallpaperTagSuggestion(title: "城市", query: "city"),
        WallpaperTagSuggestion(title: "建筑", query: "architecture"),
        WallpaperTagSuggestion(title: "太空", query: "space"),
        WallpaperTagSuggestion(title: "赛博朋克", query: "cyberpunk"),
        WallpaperTagSuggestion(title: "游戏", query: "game"),
        WallpaperTagSuggestion(title: "汽车", query: "car"),
        WallpaperTagSuggestion(title: "动漫", query: "anime"),
        WallpaperTagSuggestion(title: "日落", query: "sunset"),
        WallpaperTagSuggestion(title: "极简", query: "minimalism"),
        WallpaperTagSuggestion(title: "抽象", query: "abstract"),
        WallpaperTagSuggestion(title: "夜景", query: "night")
    ]
}

struct WallpaperSearchFilters: Equatable {
    var resolution: WallpaperResolution = .any
    var ratio: WallpaperRatio = .any
    var sorting: WallpaperSorting = .dateAdded
    var tag: String = ""
}

enum WallpaperSettingTarget: String, CaseIterable, Codable, Hashable, Identifiable {
    case desktop
    case lockScreen
    case both

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .desktop: "仅桌面壁纸"
        case .lockScreen: "仅锁屏壁纸"
        case .both: "桌面 + 锁屏"
        }
    }

    var icon: String {
        switch self {
        case .desktop: "macwindow"
        case .lockScreen: "lock"
        case .both: "macwindow.on.rectangle"
        }
    }

    var requiresLockScreen: Bool {
        self == .lockScreen || self == .both
    }
}

struct WallpaperItem: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let source: WallpaperSource
    let sourceID: String
    let title: String
    let previewURL: URL
    let originalURL: URL
    let sourcePageURL: URL?
    let authorName: String?
    let authorURL: URL?
    let width: Int
    let height: Int
    let fileExtension: String
    let licenseName: String?
    let licenseURL: URL?
    var isFavorite: Bool
    var localFileName: String?

    var aspectRatio: Double {
        guard width > 0, height > 0 else { return 16.0 / 10.0 }
        return Double(width) / Double(height)
    }

    var resolutionDescription: String {
        guard width > 0, height > 0 else { return "未知尺寸" }
        return "\(width) × \(height)"
    }
}

struct WallpaperPage {
    let items: [WallpaperItem]
    let page: Int
    let hasNextPage: Bool
}

enum WallpaperAPIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidURL: "壁纸源地址无效"
        case .invalidResponse: "壁纸源返回了无效响应"
        case let .httpStatus(status): "壁纸源请求失败（HTTP \(status)）"
        case .invalidPayload: "壁纸源数据格式无法识别"
        }
    }
}

protocol WallpaperSourceProviding {
    var source: WallpaperSource { get }

    func search(page: Int, filters: WallpaperSearchFilters) async throws -> WallpaperPage
}

enum WallpaperHTTP {
    static func data(
        for request: URLRequest,
        session: URLSession
    ) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WallpaperAPIError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw WallpaperAPIError.httpStatus(httpResponse.statusCode)
        }
        return data
    }
}

final class WallhavenWallpaperSource: WallpaperSourceProviding {
    let source: WallpaperSource = .wallhaven
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(page: Int, filters: WallpaperSearchFilters) async throws -> WallpaperPage {
        let url = try Self.searchURL(page: page, filters: filters)

        let data = try await WallpaperHTTP.data(
            for: URLRequest(url: url),
            session: session
        )
        return try Self.decode(data: data)
    }

    static func searchURL(page: Int, filters: WallpaperSearchFilters) throws -> URL {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "purity", value: "100"),
            URLQueryItem(name: "sorting", value: filters.sorting.apiValue),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "page", value: "\(max(1, page))")
        ]
        if let minimumResolution = filters.resolution.minimumResolution {
            components?.queryItems?.append(
                URLQueryItem(name: "atleast", value: minimumResolution)
            )
        }
        if let ratio = filters.ratio.apiValue {
            components?.queryItems?.append(URLQueryItem(name: "ratios", value: ratio))
        }
        let tag = filters.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "q", value: tag))
        }
        guard let url = components?.url else {
            throw WallpaperAPIError.invalidURL
        }
        return url
    }

    static func decode(data: Data) throws -> WallpaperPage {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw WallpaperAPIError.invalidPayload
        }

        let items = response.data.compactMap { remote in
            WallpaperItem(
                id: "wallhaven:\(remote.id)",
                source: .wallhaven,
                sourceID: remote.id,
                title: "Wallhaven \(remote.id)",
                previewURL: remote.thumbs.large,
                originalURL: remote.path,
                sourcePageURL: remote.url,
                authorName: remote.uploader?.username,
                authorURL: nil,
                width: remote.dimensionX,
                height: remote.dimensionY,
                fileExtension: remote.path.pathExtension.isEmpty ? "jpg" : remote.path.pathExtension,
                licenseName: "版权以原作者页面为准",
                licenseURL: nil,
                isFavorite: false,
                localFileName: nil
            )
        }

        return WallpaperPage(
            items: items,
            page: response.meta.currentPage,
            hasNextPage: response.meta.currentPage < response.meta.lastPage
        )
    }

    private struct Response: Decodable {
        let data: [RemoteItem]
        let meta: Meta
    }

    private struct Meta: Decodable {
        let currentPage: Int
        let lastPage: Int

        enum CodingKeys: String, CodingKey {
            case currentPage = "current_page"
            case lastPage = "last_page"
        }
    }

    private struct RemoteItem: Decodable {
        let id: String
        let url: URL
        let path: URL
        let dimensionX: Int
        let dimensionY: Int
        let thumbs: Thumbnails
        let uploader: Uploader?

        enum CodingKeys: String, CodingKey {
            case id, url, path, thumbs, uploader
            case dimensionX = "dimension_x"
            case dimensionY = "dimension_y"
        }
    }

    private struct Thumbnails: Decodable {
        let large: URL
    }

    private struct Uploader: Decodable {
        let username: String?
    }
}

enum WallpaperImageValidation {
    static func dimensions(for fileURL: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0,
              height.intValue > 0
        else {
            return nil
        }
        return CGSize(width: width.intValue, height: height.intValue)
    }

    static func isValidImage(at fileURL: URL) -> Bool {
        dimensions(for: fileURL) != nil
    }
}

final class WallpaperStore {
    private let fileManager: FileManager
    let directoryURL: URL
    private let metadataURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let directory = supportDirectory
            .appendingPathComponent(JarvisAppIdentity.dataDirectoryName, isDirectory: true)
            .appendingPathComponent("Wallpapers", isDirectory: true)
        directoryURL = directory
        metadataURL = directory.appendingPathComponent("metadata.json")
        JarvisProtectedStorage.prepareDirectory(directory, fileManager: fileManager)
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        metadataURL = directoryURL.appendingPathComponent("metadata.json")
        JarvisProtectedStorage.prepareDirectory(directoryURL, fileManager: fileManager)
    }

    func load() -> [WallpaperItem] {
        loadWithoutValidatingFiles().filter { localURL(for: $0) != nil }
    }

    func loadFavorites() -> [WallpaperItem] {
        loadWithoutValidatingFiles().filter(\.isFavorite)
    }

    func localURL(for item: WallpaperItem) -> URL? {
        guard let fileName = item.localFileName,
              isSafeFileName(fileName)
        else {
            return nil
        }
        let url = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        guard url.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL,
              fileManager.fileExists(atPath: url.path),
              WallpaperImageValidation.isValidImage(at: url)
        else {
            return nil
        }
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true
        {
            return nil
        }
        return url
    }

    @discardableResult
    func save(downloadedFileURL: URL, for item: WallpaperItem) throws -> WallpaperItem {
        guard WallpaperImageValidation.isValidImage(at: downloadedFileURL) else {
            throw WallpaperStoreError.invalidImage
        }

        let extensionName = safeExtension(item.fileExtension)
        let fileName = item.localFileName ?? "wallpaper-\(UUID().uuidString).\(extensionName)"
        guard isSafeFileName(fileName) else { throw WallpaperStoreError.invalidFilename }
        let destinationURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: downloadedFileURL, to: destinationURL)

        var savedItem = item
        savedItem.localFileName = fileName
        try upsert(savedItem)
        return savedItem
    }

    func delete(_ item: WallpaperItem) throws {
        if let fileName = item.localFileName {
            guard isSafeFileName(fileName) else { throw WallpaperStoreError.invalidFilename }
            let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
            guard fileURL.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL else {
                throw WallpaperStoreError.invalidFilename
            }
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }

        var items = loadWithoutValidatingFiles()
        items.removeAll { $0.id == item.id }
        let data = try JSONEncoder().encode(items)
        try data.write(to: metadataURL, options: .atomic)
    }

    func upsert(_ item: WallpaperItem) throws {
        var items = loadWithoutValidatingFiles()
        if let existing = items.first(where: { $0.id == item.id }) {
            var merged = item
            merged.localFileName = item.localFileName ?? existing.localFileName
            items.removeAll { $0.id == item.id }
            if merged.isFavorite || merged.localFileName != nil {
                items.insert(merged, at: 0)
            }
        } else {
            if item.isFavorite || item.localFileName != nil {
                items.insert(item, at: 0)
            }
        }
        let data = try JSONEncoder().encode(items)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func loadWithoutValidatingFiles() -> [WallpaperItem] {
        guard let data = try? Data(contentsOf: metadataURL),
              let items = try? JSONDecoder().decode([WallpaperItem].self, from: data)
        else {
            return []
        }
        return items
    }

    private func isSafeFileName(_ fileName: String) -> Bool {
        let prefix = "wallpaper-"
        let components = fileName.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard fileName.hasPrefix(prefix),
              components.count == 2,
              UUID(uuidString: String(components[0].dropFirst(prefix.count))) != nil,
              !components[1].isEmpty
        else {
            return false
        }
        return true
    }

    private func safeExtension(_ value: String) -> String {
        let filtered = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return filtered.isEmpty ? "jpg" : String(filtered.prefix(8))
    }
}

enum WallpaperStoreError: LocalizedError, Equatable {
    case invalidImage
    case invalidFilename

    var errorDescription: String? {
        switch self {
        case .invalidImage: "文件不是有效的图片"
        case .invalidFilename: "壁纸文件名无效"
        }
    }
}

final class WallpaperDownloadService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "wallhaven.cc" || host.hasSuffix(".wallhaven.cc")
    }

    func download(from url: URL) async throws -> URL {
        guard Self.isAllowedDownloadURL(url) else {
            throw WallpaperAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        let (temporaryURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WallpaperAPIError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw WallpaperAPIError.httpStatus(httpResponse.statusCode)
        }
        return temporaryURL
    }
}

enum DesktopWallpaperServiceError: LocalizedError, Equatable {
    case noScreens
    case lockScreenUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noScreens: "没有找到可设置的显示器"
        case .lockScreenUnavailable: "macOS 不支持通过公开接口直接设置锁屏壁纸，请在系统设置中完成"
        case let .failed(message): "桌面壁纸设置失败：\(message)"
        }
    }
}

@MainActor
struct DesktopWallpaperService {
    private let screensProvider: () -> [NSScreen]
    private let setImage: (URL, NSScreen, [NSWorkspace.DesktopImageOptionKey: Any]) throws -> Void

    init(
        screensProvider: @escaping () -> [NSScreen] = { NSScreen.screens },
        setImage: @escaping (URL, NSScreen, [NSWorkspace.DesktopImageOptionKey: Any]) throws -> Void = {
            imageURL,
            screen,
            options in
            try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: options)
        }
    ) {
        self.screensProvider = screensProvider
        self.setImage = setImage
    }

    func apply(imageURL: URL, target: WallpaperSettingTarget) throws {
        guard !target.requiresLockScreen else {
            throw DesktopWallpaperServiceError.lockScreenUnavailable
        }

        let screens = screensProvider()
        guard !screens.isEmpty else {
            throw DesktopWallpaperServiceError.noScreens
        }

        guard imageURL.isFileURL,
              FileManager.default.fileExists(atPath: imageURL.path)
        else {
            throw DesktopWallpaperServiceError.failed("壁纸文件不存在或不是本地文件")
        }

        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
            .allowClipping: true
        ]
        var previous: [(screen: NSScreen, url: URL?, options: [NSWorkspace.DesktopImageOptionKey: Any])] = []

        do {
            for screen in screens {
                previous.append(
                    (
                        screen: screen,
                        url: NSWorkspace.shared.desktopImageURL(for: screen),
                        options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
                    )
                )
                try setImage(imageURL, screen, options)
            }
        } catch {
            for item in previous {
                guard let previousURL = item.url else { continue }
                try? setImage(previousURL, item.screen, item.options)
            }
            throw DesktopWallpaperServiceError.failed(error.localizedDescription)
        }
    }
}

enum WallpaperSystemServiceError: LocalizedError, Equatable {
    case invalidWallpaper
    case wallpaperStoreUnavailable
    case loginWindowUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidWallpaper:
            "壁纸文件不存在或不是有效图片"
        case .wallpaperStoreUnavailable:
            "无法更新 macOS 的统一壁纸记录"
        case .loginWindowUnavailable:
            "无法更新 macOS 的登录界面壁纸记录"
        case let .failed(message):
            "壁纸同步失败：\(message)"
        }
    }
}

/// Keeps the desktop, idle/lock-screen, and login-window records on one image.
///
/// macOS exposes the desktop image through NSWorkspace, but does not expose a
/// public API for the other two records. The latter are still user-scoped
/// system records, so we update them together and validate the writes.
@MainActor
struct WallpaperSystemService {
    private let fileManager: FileManager
    private let desktopWallpaperService: DesktopWallpaperService
    private let wallpaperIndexURL: URL
    private let stableWallpaperDirectoryURL: URL
    private let setLoginWindowWallpaper: @MainActor (URL?) throws -> Void
    private let refreshWallpaperAgent: @MainActor () throws -> Void

    init(
        desktopWallpaperService: DesktopWallpaperService? = nil,
        fileManager: FileManager = .default,
        wallpaperIndexURL: URL? = nil,
        stableWallpaperDirectoryURL: URL? = nil,
        setLoginWindowWallpaper: (@MainActor (URL?) throws -> Void)? = nil,
        refreshWallpaperAgent: (@MainActor () throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.desktopWallpaperService = desktopWallpaperService ?? DesktopWallpaperService()

        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        self.wallpaperIndexURL = wallpaperIndexURL ?? homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("Store", isDirectory: true)
            .appendingPathComponent("Index.plist", isDirectory: false)

        let applicationSupportDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        self.stableWallpaperDirectoryURL = stableWallpaperDirectoryURL ?? applicationSupportDirectory
            .appendingPathComponent(JarvisAppIdentity.dataDirectoryName, isDirectory: true)
            .appendingPathComponent("SystemWallpaper", isDirectory: true)

        self.setLoginWindowWallpaper = setLoginWindowWallpaper ?? WallpaperSystemService.writeLoginWindowWallpaper
        self.refreshWallpaperAgent = refreshWallpaperAgent ?? WallpaperSystemService.refreshWallpaperAgent
    }

    func apply(imageURL: URL, target: WallpaperSettingTarget) throws {
        guard imageURL.isFileURL,
              fileManager.fileExists(atPath: imageURL.path),
              WallpaperImageValidation.isValidImage(at: imageURL)
        else {
            throw WallpaperSystemServiceError.invalidWallpaper
        }

        let stableURL = try makeStableWallpaperCopy(from: imageURL)
        let previousWallpaperIndexData: Data
        let previousLoginWindowWallpaper: URL?

        do {
            previousWallpaperIndexData = try Data(contentsOf: wallpaperIndexURL)
        } catch {
            throw WallpaperSystemServiceError.failed("无法读取原有壁纸记录：\(error.localizedDescription)")
        }

        if target.requiresLockScreen {
            previousLoginWindowWallpaper = Self.readLoginWindowWallpaper()
        } else {
            previousLoginWindowWallpaper = nil
        }

        do {
            if target == .desktop || target == .both {
                // NSWorkspace rewrites Index.plist. It must run before our
                // unified write, otherwise it restores stale Idle records and
                // removes the AllSpacesAndDisplays desktop configuration.
                try desktopWallpaperService.apply(imageURL: stableURL, target: .desktop)
            }

            try updateWallpaperIndex(to: stableURL, target: target)

            if target.requiresLockScreen {
                try setLoginWindowWallpaper(stableURL)
            }

            try refreshWallpaperAgent()
        } catch {
            try? previousWallpaperIndexData.write(to: wallpaperIndexURL, options: .atomic)
            try? refreshWallpaperAgent()
            if target.requiresLockScreen {
                try? setLoginWindowWallpaper(previousLoginWindowWallpaper)
            }
            throw error
        }
    }

    private func makeStableWallpaperCopy(from sourceURL: URL) throws -> URL {
        do {
            try fileManager.createDirectory(
                at: stableWallpaperDirectoryURL,
                withIntermediateDirectories: true
            )

            let extensionName = sourceURL.pathExtension
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
            let stableURL = stableWallpaperDirectoryURL
                .appendingPathComponent(
                    "active-wallpaper.\(extensionName.isEmpty ? "jpg" : extensionName)",
                    isDirectory: false
                )
            let temporaryURL = stableWallpaperDirectoryURL
                .appendingPathComponent(
                    ".active-wallpaper-\(UUID().uuidString).tmp",
                    isDirectory: false
                )

            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
            defer { try? fileManager.removeItem(at: temporaryURL) }

            if fileManager.fileExists(atPath: stableURL.path) {
                try fileManager.removeItem(at: stableURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: stableURL)
            return stableURL
        } catch {
            throw WallpaperSystemServiceError.failed("无法保存稳定的系统壁纸副本：\(error.localizedDescription)")
        }
    }

    private func updateWallpaperIndex(to imageURL: URL, target: WallpaperSettingTarget) throws {
        do {
            let sourceData = try Data(contentsOf: wallpaperIndexURL)
            guard let propertyList = try PropertyListSerialization.propertyList(
                from: sourceData,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw WallpaperSystemServiceError.wallpaperStoreUnavailable
            }

            let configuration = try imageConfigurationData(for: imageURL)
            var updatedPropertyList: Any = propertyList
            var updateCount = 0

            if target == .desktop || target == .both,
               let root = updatedPropertyList as? [String: Any]
            {
                let (updatedRoot, desktopUpdateCount) = replacingDesktopConfigurations(
                    in: root,
                    with: configuration
                )
                updatedPropertyList = updatedRoot
                updateCount += desktopUpdateCount
            }

            if target.requiresLockScreen {
                let (updatedValue, idleUpdateCount) = replacingIdleConfigurations(
                    in: updatedPropertyList,
                    with: configuration
                )
                updatedPropertyList = updatedValue
                updateCount += idleUpdateCount
            }

            guard updateCount > 0 else {
                throw WallpaperSystemServiceError.wallpaperStoreUnavailable
            }

            let updatedData = try PropertyListSerialization.data(
                fromPropertyList: updatedPropertyList,
                format: .binary,
                options: 0
            )
            try updatedData.write(to: wallpaperIndexURL, options: .atomic)
        } catch let error as WallpaperSystemServiceError {
            throw error
        } catch {
            throw WallpaperSystemServiceError.failed("无法写入锁屏壁纸记录：\(error.localizedDescription)")
        }
    }

    private func replacingDesktopConfigurations(
        in root: [String: Any],
        with configuration: Data
    ) -> ([String: Any], Int) {
        let (updatedValue, existingUpdateCount) = replacingDesktopConfigurations(
            in: root as Any,
            with: configuration
        )
        guard var updatedRoot = updatedValue as? [String: Any] else {
            return (root, 0)
        }

        var allSpaces = dictionary(updatedRoot["AllSpacesAndDisplays"])
        var updateCount = existingUpdateCount
        var desktop = dictionary(allSpaces["Desktop"])
        if desktopChoices(in: desktop).isEmpty {
            let fallbackDesktop = desktopConfiguration(in: root)
            let (fallback, fallbackUpdateCount) = replacingDesktopSection(
                fallbackDesktop,
                with: configuration
            )
            desktop = fallback
            updateCount += fallbackUpdateCount
        }

        guard !desktopChoices(in: desktop).isEmpty else {
            return (root, 0)
        }

        allSpaces["Desktop"] = desktop
        allSpaces["Type"] = "desktop"
        updatedRoot["AllSpacesAndDisplays"] = allSpaces
        return (updatedRoot, max(updateCount, 1))
    }

    private func replacingDesktopConfigurations(
        in value: Any,
        with configuration: Data
    ) -> (Any, Int) {
        if var dictionary = value as? [String: Any] {
            var updateCount = 0

            if let desktop = dictionary["Desktop"] as? [String: Any] {
                let (updatedDesktop, desktopUpdateCount) = replacingDesktopSection(
                    desktop,
                    with: configuration
                )
                dictionary["Desktop"] = updatedDesktop
                updateCount += desktopUpdateCount
            }

            for key in dictionary.keys where key != "Desktop" {
                let (updatedValue, nestedUpdateCount) = replacingDesktopConfigurations(
                    in: dictionary[key] as Any,
                    with: configuration
                )
                dictionary[key] = updatedValue
                updateCount += nestedUpdateCount
            }
            return (dictionary, updateCount)
        }

        if var array = value as? [Any] {
            var updateCount = 0
            for index in array.indices {
                let (updatedValue, nestedUpdateCount) = replacingDesktopConfigurations(
                    in: array[index],
                    with: configuration
                )
                array[index] = updatedValue
                updateCount += nestedUpdateCount
            }
            return (array, updateCount)
        }

        return (value, 0)
    }

    private func replacingDesktopSection(
        _ desktop: [String: Any],
        with configuration: Data
    ) -> ([String: Any], Int) {
        var desktop = desktop
        var content = dictionary(desktop["Content"])
        var choices = desktopChoices(in: desktop)
        guard !choices.isEmpty else {
            return (desktop, 0)
        }

        for index in choices.indices {
            choices[index]["Configuration"] = configuration
            choices[index]["Files"] = [Any]()
            choices[index]["Provider"] = "com.apple.wallpaper.choice.image"
        }
        content["Choices"] = choices
        content["Shuffle"] = content["Shuffle"] ?? "$null"
        desktop["Content"] = content
        desktop["LastSet"] = Date()
        desktop["LastUse"] = Date()
        return (desktop, choices.count)
    }

    private func desktopChoices(in desktop: [String: Any]) -> [[String: Any]] {
        let content = dictionary(desktop["Content"])
        return dictionaryArray(content["Choices"])
    }

    private func desktopConfiguration(in root: [String: Any]) -> [String: Any] {
        if let systemDefaultDesktop = dictionary(root["SystemDefault"])["Desktop"] as? [String: Any] {
            return systemDefaultDesktop
        }

        let spaces = dictionary(root["Spaces"])
        for space in spaces.values {
            if let defaultDesktop = dictionary(dictionary(space)["Default"])["Desktop"] as? [String: Any] {
                return defaultDesktop
            }
        }

        return [:]
    }

    private func dictionary(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    private func dictionaryArray(_ value: Any?) -> [[String: Any]] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { $0 as? [String: Any] }
    }

    private func imageConfigurationData(for imageURL: URL) throws -> Data {
        let configuration: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": imageURL.absoluteString]
        ]
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: configuration,
                format: .binary,
                options: 0
            )
        } catch {
            throw WallpaperSystemServiceError.failed("无法生成锁屏壁纸配置：\(error.localizedDescription)")
        }
    }

    private func replacingIdleConfigurations(
        in value: Any,
        with configuration: Data
    ) -> (Any, Int) {
        if var dictionary = value as? [String: Any] {
            var updateCount = 0

            if var idle = dictionary["Idle"] as? [String: Any],
               var content = idle["Content"] as? [String: Any],
               var choices = content["Choices"] as? [[String: Any]],
               !choices.isEmpty
            {
                for index in choices.indices {
                    choices[index]["Configuration"] = configuration
                    choices[index]["Files"] = [Any]()
                    choices[index]["Provider"] = "com.apple.wallpaper.choice.image"
                }
                content["Choices"] = choices
                idle["Content"] = content
                dictionary["Idle"] = idle
                updateCount += choices.count
            }

            for key in dictionary.keys where key != "Idle" {
                let (updatedValue, nestedUpdateCount) = replacingIdleConfigurations(
                    in: dictionary[key] as Any,
                    with: configuration
                )
                dictionary[key] = updatedValue
                updateCount += nestedUpdateCount
            }
            return (dictionary, updateCount)
        }

        if var array = value as? [Any] {
            var updateCount = 0
            for index in array.indices {
                let (updatedValue, nestedUpdateCount) = replacingIdleConfigurations(
                    in: array[index],
                    with: configuration
                )
                array[index] = updatedValue
                updateCount += nestedUpdateCount
            }
            return (array, updateCount)
        }

        return (value, 0)
    }

    private static func writeLoginWindowWallpaper(_ imageURL: URL?) throws {
        let applicationID = "com.apple.loginwindow" as CFString
        let key = "DesktopPicture" as CFString
        let value = imageURL.map { $0.path as CFString }
        CFPreferencesSetAppValue(key, value, applicationID)
        guard CFPreferencesAppSynchronize(applicationID) else {
            throw WallpaperSystemServiceError.loginWindowUnavailable
        }
        let storedValue = CFPreferencesCopyAppValue(key, applicationID) as? String
        guard storedValue == imageURL?.path else {
            throw WallpaperSystemServiceError.loginWindowUnavailable
        }
    }

    private static func readLoginWindowWallpaper() -> URL? {
        let applicationID = "com.apple.loginwindow" as CFString
        let key = "DesktopPicture" as CFString
        guard let path = CFPreferencesCopyAppValue(key, applicationID) as? String,
              !path.isEmpty
        else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private static func refreshWallpaperAgent() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw WallpaperSystemServiceError.failed("无法刷新 macOS 壁纸服务")
        }
    }
}

@MainActor
final class WallpaperViewModel: ObservableObject {
    static let initialDisplayCount = 36
    private static let loadMoreDisplayCount = 24

    @Published var selectedResolution: WallpaperResolution = .any
    @Published var selectedRatio: WallpaperRatio = .any
    @Published var selectedSorting: WallpaperSorting = .dateAdded
    @Published var selectedTag = ""
    @Published private(set) var items: [WallpaperItem] = []
    @Published private(set) var library: [WallpaperItem] = []
    @Published private(set) var favorites: [WallpaperItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasNextPage = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadMoreErrorMessage: String?
    @Published private(set) var downloadingIDs: Set<String> = []
    @Published private(set) var appliedWallpaperID: String?

    private var searchGeneration = 0
    let store: WallpaperStore
    private let wallhavenSource: WallhavenWallpaperSource
    private let downloader: WallpaperDownloadService
    private let wallpaperSystemService: WallpaperSystemService
    private var currentPage = 1
    private var currentFilters = WallpaperSearchFilters()
    private var bufferedItems: [WallpaperItem] = []
    private var canFetchMorePages = false

    init(
        store: WallpaperStore = WallpaperStore(),
        wallhavenSource: WallhavenWallpaperSource = WallhavenWallpaperSource(),
        downloader: WallpaperDownloadService = WallpaperDownloadService(),
        desktopWallpaperService: DesktopWallpaperService? = nil,
        wallpaperSystemService: WallpaperSystemService? = nil
    ) {
        self.store = store
        self.wallhavenSource = wallhavenSource
        self.downloader = downloader
        let desktopService = desktopWallpaperService ?? DesktopWallpaperService()
        self.wallpaperSystemService = wallpaperSystemService ?? WallpaperSystemService(
            desktopWallpaperService: desktopService,
            stableWallpaperDirectoryURL: store.directoryURL.appendingPathComponent(
                "SystemWallpaper",
                isDirectory: true
            )
        )
        library = store.load()
        favorites = store.loadFavorites()
    }

    func refresh() async {
        searchGeneration += 1
        let generation = searchGeneration
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        loadMoreErrorMessage = nil
        currentPage = 1
        currentFilters = WallpaperSearchFilters(
            resolution: selectedResolution,
            ratio: selectedRatio,
            sorting: selectedSorting,
            tag: selectedTag
        )
        defer { isLoading = false }

        do {
            var page = try await wallhavenSource.search(page: 1, filters: currentFilters)
            var loadedItems = mergeWithSavedItems(page.items)

            while loadedItems.count < Self.initialDisplayCount, page.hasNextPage {
                guard generation == searchGeneration else { return }
                page = try await wallhavenSource.search(page: page.page + 1, filters: currentFilters)
                loadedItems.append(contentsOf: mergeWithSavedItems(page.items))
            }

            guard generation == searchGeneration else { return }
            items = Array(loadedItems.prefix(Self.initialDisplayCount))
            bufferedItems = Array(loadedItems.dropFirst(items.count))
            currentPage = page.page
            canFetchMorePages = page.hasNextPage
            hasNextPage = !bufferedItems.isEmpty || canFetchMorePages
        } catch {
            guard generation == searchGeneration else { return }
            items = []
            bufferedItems = []
            canFetchMorePages = false
            hasNextPage = false
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasNextPage else { return }
        let generation = searchGeneration
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer { isLoadingMore = false }

        do {
            var nextItems = Array(bufferedItems.prefix(Self.loadMoreDisplayCount))
            var nextBufferedItems = Array(bufferedItems.dropFirst(nextItems.count))
            var nextPage = currentPage
            var nextCanFetchMorePages = canFetchMorePages

            while nextItems.count < Self.loadMoreDisplayCount, nextCanFetchMorePages {
                let page = try await wallhavenSource.search(
                    page: nextPage + 1,
                    filters: currentFilters
                )
                nextPage = page.page
                let pageItems = mergeWithSavedItems(page.items)
                let remainingCount = Self.loadMoreDisplayCount - nextItems.count
                nextItems.append(contentsOf: pageItems.prefix(remainingCount))
                nextBufferedItems.append(contentsOf: pageItems.dropFirst(remainingCount))
                nextCanFetchMorePages = page.hasNextPage
            }

            guard generation == searchGeneration else { return }
            items.append(contentsOf: nextItems)
            bufferedItems = nextBufferedItems
            currentPage = nextPage
            canFetchMorePages = nextCanFetchMorePages
            hasNextPage = !bufferedItems.isEmpty || canFetchMorePages
        } catch {
            guard generation == searchGeneration else { return }
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    func refreshLibrary() {
        library = store.load()
        favorites = store.loadFavorites()
        items = mergeWithSavedItems(items)
    }

    @discardableResult
    func toggleFavorite(_ item: WallpaperItem) -> WallpaperItem? {
        var updated = item
        updated.isFavorite.toggle()
        do {
            try store.upsert(updated)
            items = items.map { currentItem in
                guard currentItem.id == updated.id else { return currentItem }
                var refreshedItem = currentItem
                refreshedItem.isFavorite = updated.isFavorite
                return refreshedItem
            }
            refreshLibrary()
            return updated
        } catch {
            errorMessage = "收藏状态保存失败：\(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func delete(_ item: WallpaperItem) -> Bool {
        do {
            try store.delete(item)
            refreshLibrary()
            return true
        } catch {
            errorMessage = "删除壁纸失败：\(error.localizedDescription)"
            return false
        }
    }

    func localURL(for item: WallpaperItem) -> URL? {
        store.localURL(for: item)
    }

    func isDownloading(_ item: WallpaperItem) -> Bool {
        downloadingIDs.contains(item.id)
    }

    func isApplied(_ item: WallpaperItem) -> Bool {
        appliedWallpaperID == item.id
    }

    func downloadAndApply(
        _ item: WallpaperItem,
        target: WallpaperSettingTarget
    ) async -> String {
        guard !downloadingIDs.contains(item.id) else { return "正在处理这张壁纸…" }

        downloadingIDs.insert(item.id)
        defer { downloadingIDs.remove(item.id) }

        do {
            let savedItem: WallpaperItem
            if store.localURL(for: item) != nil {
                savedItem = item
            } else {
                let temporaryURL = try await downloader.download(from: item.originalURL)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                savedItem = try store.save(downloadedFileURL: temporaryURL, for: item)
            }

            guard let localURL = store.localURL(for: savedItem) else {
                return "壁纸已下载，但本地文件不可用"
            }
            try wallpaperSystemService.apply(imageURL: localURL, target: target)
            appliedWallpaperID = savedItem.id
            refreshLibrary()
            return "设置成功"
        } catch {
            return error.localizedDescription
        }
    }

    private func mergeWithSavedItems(_ incoming: [WallpaperItem]) -> [WallpaperItem] {
        var savedByID = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        for favorite in favorites {
            savedByID[favorite.id] = favorite
        }
        return incoming.map { item in
            var merged = item
            guard let saved = savedByID[item.id] else {
                merged.isFavorite = false
                return merged
            }
            merged.isFavorite = saved.isFavorite
            merged.localFileName = saved.localFileName
            return merged
        }
    }
}

enum WallpaperSystemSettings {
    static func open() {
        let urls = [
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect"
        ].compactMap(URL.init(string:))
        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }
}

enum WallpaperImageLoader {
    private static let imageCache = NSCache<NSString, NSImage>()

    static func loadOriginal(url: URL) async -> NSImage? {
        let data: Data
        do {
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                data = try await WallpaperHTTP.data(
                    for: URLRequest(url: url),
                    session: .shared
                )
            }
        } catch {
            return nil
        }

        guard let image = NSImage(data: data),
              image.size.width > 0,
              image.size.height > 0
        else {
            return nil
        }
        return image
    }

    static func load(url: URL, maxPixelSize: Int = 900) async -> NSImage? {
        let cacheKey = "\(url.absoluteString)|\(maxPixelSize)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let data: Data
        do {
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (remoteData, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200 ..< 300).contains(httpResponse.statusCode)
                else {
                    return nil
                }
                data = remoteData
            }
        } catch {
            return nil
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                  ] as CFDictionary
              )
        else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }
}
