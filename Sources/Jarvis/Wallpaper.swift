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

enum WallpaperCategory: String, CaseIterable, Codable, Hashable, Identifiable {
    case all
    case general
    case anime
    case people
    case generalAnime
    case generalPeople
    case animePeople

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "全部分类"
        case .general: "通用"
        case .anime: "动漫"
        case .people: "人物"
        case .generalAnime: "通用 + 动漫"
        case .generalPeople: "通用 + 人物"
        case .animePeople: "动漫 + 人物"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: "全部"
        case .general: "通用"
        case .anime: "动漫"
        case .people: "人物"
        case .generalAnime: "通用 + 动漫"
        case .generalPeople: "通用 + 人物"
        case .animePeople: "动漫 + 人物"
        }
    }

    var apiValue: String {
        switch self {
        case .all: "111"
        case .general: "100"
        case .anime: "010"
        case .people: "001"
        case .generalAnime: "110"
        case .generalPeople: "101"
        case .animePeople: "011"
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
    var category: WallpaperCategory = .all
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
            URLQueryItem(name: "categories", value: filters.category.apiValue),
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
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        metadataURL = directoryURL.appendingPathComponent("metadata.json")
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
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

    func download(from url: URL) async throws -> URL {
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
        case .lockScreenUnavailable: "当前 macOS 不提供第三方直接设置锁屏壁纸的公开接口"
        case let .failed(message): "桌面壁纸设置失败：\(message)"
        }
    }
}

@MainActor
struct DesktopWallpaperService {
    private let screensProvider: () -> [NSScreen]
    private let allSpacesStore: AllSpacesWallpaperStore

    init(
        screensProvider: @escaping () -> [NSScreen] = { NSScreen.screens },
        allSpacesStore: AllSpacesWallpaperStore = AllSpacesWallpaperStore()
    ) {
        self.screensProvider = screensProvider
        self.allSpacesStore = allSpacesStore
    }

    func apply(imageURL: URL, target: WallpaperSettingTarget) throws {
        guard !target.requiresLockScreen else {
            throw DesktopWallpaperServiceError.lockScreenUnavailable
        }

        let screens = screensProvider()
        guard !screens.isEmpty else {
            throw DesktopWallpaperServiceError.noScreens
        }

        do {
            try allSpacesStore.apply(imageURL: imageURL)
        } catch {
            throw DesktopWallpaperServiceError.failed(error.localizedDescription)
        }
    }
}

@MainActor
final class WallpaperViewModel: ObservableObject {
    static let initialDisplayCount = 36
    private static let loadMoreDisplayCount = 24

    @Published var selectedResolution: WallpaperResolution = .any
    @Published var selectedCategory: WallpaperCategory = .all
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

    let store: WallpaperStore
    private let wallhavenSource: WallhavenWallpaperSource
    private let downloader: WallpaperDownloadService
    private let desktopWallpaperService: DesktopWallpaperService
    private var currentPage = 1
    private var currentFilters = WallpaperSearchFilters()
    private var bufferedItems: [WallpaperItem] = []
    private var canFetchMorePages = false

    init(
        store: WallpaperStore = WallpaperStore(),
        wallhavenSource: WallhavenWallpaperSource = WallhavenWallpaperSource(),
        downloader: WallpaperDownloadService = WallpaperDownloadService(),
        desktopWallpaperService: DesktopWallpaperService? = nil
    ) {
        self.store = store
        self.wallhavenSource = wallhavenSource
        self.downloader = downloader
        self.desktopWallpaperService = desktopWallpaperService ?? DesktopWallpaperService()
        library = store.load()
        favorites = store.loadFavorites()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        loadMoreErrorMessage = nil
        currentPage = 1
        currentFilters = WallpaperSearchFilters(
            resolution: selectedResolution,
            category: selectedCategory,
            ratio: selectedRatio,
            sorting: selectedSorting,
            tag: selectedTag
        )
        defer { isLoading = false }

        do {
            var page = try await wallhavenSource.search(page: 1, filters: currentFilters)
            var loadedItems = mergeWithSavedItems(page.items)

            while loadedItems.count < Self.initialDisplayCount, page.hasNextPage {
                page = try await wallhavenSource.search(page: page.page + 1, filters: currentFilters)
                loadedItems.append(contentsOf: mergeWithSavedItems(page.items))
            }

            items = Array(loadedItems.prefix(Self.initialDisplayCount))
            bufferedItems = Array(loadedItems.dropFirst(items.count))
            currentPage = page.page
            canFetchMorePages = page.hasNextPage
            hasNextPage = !bufferedItems.isEmpty || canFetchMorePages
        } catch {
            items = []
            bufferedItems = []
            canFetchMorePages = false
            hasNextPage = false
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasNextPage else { return }
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

            items.append(contentsOf: nextItems)
            bufferedItems = nextBufferedItems
            currentPage = nextPage
            canFetchMorePages = nextCanFetchMorePages
            hasNextPage = !bufferedItems.isEmpty || canFetchMorePages
        } catch {
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    func refreshLibrary() {
        library = store.load()
        favorites = store.loadFavorites()
        items = mergeWithSavedItems(items)
    }

    func toggleFavorite(_ item: WallpaperItem) {
        var updated = item
        updated.isFavorite.toggle()
        do {
            try store.upsert(updated)
            refreshLibrary()
        } catch {
            errorMessage = "收藏状态保存失败：\(error.localizedDescription)"
        }
    }

    func delete(_ item: WallpaperItem) {
        do {
            try store.delete(item)
            refreshLibrary()
        } catch {
            errorMessage = "删除壁纸失败：\(error.localizedDescription)"
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
        guard !target.requiresLockScreen else {
            return DesktopWallpaperServiceError.lockScreenUnavailable.localizedDescription
        }
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
            try desktopWallpaperService.apply(imageURL: localURL, target: target)
            appliedWallpaperID = savedItem.id
            refreshLibrary()
            return "已替换桌面壁纸（所有显示器和空间）"
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
            guard let saved = savedByID[item.id] else { return item }
            var merged = item
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
