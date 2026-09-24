import AppKit
import Foundation
import ImageIO

enum WallpaperSource: String, CaseIterable, Codable, Hashable, Identifiable {
    case wallhaven
    case qihoo
    /// Kept for decoding older local-library records.
    case wikimedia
    /// Kept for decoding older local-library records.
    case local

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .wallhaven: "Wallhaven"
        case .qihoo: "360壁纸"
        case .wikimedia: "Wikimedia"
        case .local: "本地"
        }
    }

    var icon: String {
        switch self {
        case .wallhaven: "photo.on.rectangle.angled"
        case .qihoo: "photo.stack"
        case .wikimedia: "globe"
        case .local: "folder"
        }
    }

    /// Sources the online gallery can switch between. Local/Wikimedia exist
    /// only so older saved records still decode.
    static var onlineGalleryCases: [WallpaperSource] {
        [.wallhaven, .qihoo]
    }
}

enum WallpaperSourcePreferences {
    static let storageKey = "wallpaper.enabledSources"
    static let defaultStorageValue = WallpaperSource.onlineGalleryCases
        .map(\.rawValue)
        .joined(separator: ",")

    static func enabledSources(from storageValue: String) -> [WallpaperSource] {
        let storedIDs = Set(storageValue.split(separator: ",").map(String.init))
        let enabled = WallpaperSource.onlineGalleryCases.filter { storedIDs.contains($0.rawValue) }
        return enabled.isEmpty ? [.wallhaven] : enabled
    }

    static func storageValue(for sources: [WallpaperSource]) -> String {
        WallpaperSource.onlineGalleryCases
            .filter(sources.contains)
            .map(\.rawValue)
            .joined(separator: ",")
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
    case custom

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
        case .custom: "自定义"
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
        case .custom: "自定义"
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
        case .custom: nil
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
    case fortyEightByNine
    case nineByEighteen
    case threeByTwo
    case fourByThree
    case fiveByFour

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
        case .fortyEightByNine: "48:9"
        case .nineByEighteen: "9:18"
        case .threeByTwo: "3:2"
        case .fourByThree: "4:3"
        case .fiveByFour: "5:4"
        }
    }

    var apiValue: String? {
        switch self {
        case .any: nil
        case .landscape: "16x9,16x10,21x9,32x9,48x9,3x2,4x3,5x4"
        case .portrait: "9x16,10x16,9x18"
        case .square: "1x1"
        case .sixteenByNine: "16x9"
        case .sixteenByTen: "16x10"
        case .twentyOneByNine: "21x9"
        case .thirtyTwoByNine: "32x9"
        case .nineBySixteen: "9x16"
        case .tenBySixteen: "10x16"
        case .fortyEightByNine: "48x9"
        case .nineByEighteen: "9x18"
        case .threeByTwo: "3x2"
        case .fourByThree: "4x3"
        case .fiveByFour: "5x4"
        }
    }
}

enum WallpaperSorting: String, CaseIterable, Codable, Hashable, Identifiable {
    case toplist
    case dateAdded
    case relevance
    case views
    case favorites
    case random

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .toplist: "热门榜"
        case .dateAdded: "最新"
        case .relevance: "相关"
        case .views: "浏览量"
        case .favorites: "收藏数"
        case .random: "随机"
        }
    }

    var apiValue: String {
        switch self {
        case .toplist: "toplist"
        case .dateAdded: "date_added"
        case .relevance: "relevance"
        case .views: "views"
        case .favorites: "favorites"
        case .random: "random"
        }
    }
}

enum WallpaperPurityPreset: String, CaseIterable, Hashable, Identifiable {
    case automatic = "auto"
    case sfw = "110"
    case nsfw = "001"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .automatic: "自动纯度"
        case .sfw: "SFW"
        case .nsfw: "NSFW"
        }
    }

    var purities: Set<WallpaperPurity>? {
        switch self {
        case .automatic: nil
        case .sfw: [.sfw, .sketchy]
        case .nsfw: [.nsfw]
        }
    }
}

enum WallpaperPurity: String, CaseIterable, Hashable, Identifiable {
    case sfw
    case sketchy
    case nsfw

    var id: String {
        rawValue
    }
}

enum WallpaperTopRange: String, CaseIterable, Hashable, Identifiable {
    case day
    case threeDays
    case week
    case month
    case threeMonths
    case sixMonths
    case year

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .day: "最近 1 天"
        case .threeDays: "最近 3 天"
        case .week: "最近 1 周"
        case .month: "最近 1 个月"
        case .threeMonths: "最近 3 个月"
        case .sixMonths: "最近 6 个月"
        case .year: "最近 1 年"
        }
    }

    var apiValue: String {
        switch self {
        case .day: "1d"
        case .threeDays: "3d"
        case .week: "1w"
        case .month: "1M"
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .year: "1y"
        }
    }
}

enum WallpaperColor: String, CaseIterable, Hashable, Identifiable {
    case darkRed = "660000"
    case red = "990000"
    case crimson = "cc0000"
    case lightRed = "cc3333"
    case pink = "ea4c88"
    case darkPurple = "993399"
    case purple = "663399"
    case indigo = "333399"
    case blue = "0066cc"
    case cyan = "0099cc"
    case turquoise = "66cccc"
    case lime = "77cc33"
    case green = "669900"
    case darkGreen = "336600"
    case olive = "666600"
    case yellowGreen = "999900"
    case yellow = "cccc33"
    case brightYellow = "ffff00"
    case amber = "ffcc33"
    case orange = "ff9900"
    case darkOrange = "ff6600"
    case ochre = "cc6633"
    case brown = "996633"
    case darkBrown = "663300"
    case black = "000000"
    case gray = "999999"
    case lightGray = "cccccc"
    case white = "ffffff"
    case slate = "424153"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .darkRed: "深红"
        case .red: "红"
        case .crimson: "猩红"
        case .lightRed: "浅红"
        case .pink: "粉"
        case .darkPurple: "深紫"
        case .purple: "紫"
        case .indigo: "靛蓝"
        case .blue: "蓝"
        case .cyan: "青"
        case .turquoise: "青绿"
        case .lime: "黄绿"
        case .green: "绿"
        case .darkGreen: "深绿"
        case .olive: "橄榄绿"
        case .yellowGreen: "黄绿"
        case .yellow: "黄"
        case .brightYellow: "亮黄"
        case .amber: "琥珀"
        case .orange: "橙"
        case .darkOrange: "深橙"
        case .ochre: "赭色"
        case .brown: "棕"
        case .darkBrown: "深棕"
        case .black: "黑"
        case .gray: "灰"
        case .lightGray: "浅灰"
        case .white: "白"
        case .slate: "石板灰"
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

enum WallpaperQihooCategory: String, CaseIterable, Identifiable {
    case all
    case fourK = "36"
    case girls = "6"
    case scenery = "9"
    case anime = "26"
    case games = "5"
    case cars = "12"
    case cool = "10"
    case fresh = "15"
    case stars = "11"
    case pets = "14"
    case romance = "30"
    case movies = "7"
    case festival = "13"
    case military = "22"
    case sports = "16"
    case calendar = "29"
    case typography = "35"
    case baby = "18"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "全部分类"
        case .fourK: "4K专区"
        case .girls: "美女模特"
        case .scenery: "风景大片"
        case .anime: "动漫卡通"
        case .games: "游戏壁纸"
        case .cars: "汽车天下"
        case .cool: "炫酷时尚"
        case .fresh: "小清新"
        case .stars: "明星风尚"
        case .pets: "萌宠动物"
        case .romance: "爱情美图"
        case .movies: "影视剧照"
        case .festival: "节日美图"
        case .military: "军事天地"
        case .sports: "劲爆体育"
        case .calendar: "月历壁纸"
        case .typography: "文字控"
        case .baby: "BABY秀"
        }
    }

    var cid: String? {
        self == .all ? nil : rawValue
    }
}

/// Exact sizes that appear in the 360 catalog. This is not Wallhaven's
/// "1080p and above" ladder — 360 stores a concrete `resolution` on each item.
enum WallpaperQihooResolution: String, CaseIterable, Identifiable {
    case any
    case fullHD = "1920x1080"
    case wuxga = "1920x1200"
    case qHD = "2560x1440"
    case wqxga = "2560x1600"
    case retina = "2880x1800"
    case uhd = "3840x2160"
    case dci4K = "4096x2304"
    case fiveK = "5120x2880"

    var id: String {
        rawValue
    }

    var title: String {
        guard let size else { return "不限分辨率" }
        return "\(size.width) × \(size.height)"
    }

    var size: (width: Int, height: Int)? {
        QihooWallpaperSource.parseResolution(rawValue)
    }
}

struct WallpaperSearchFilters: Equatable {
    var resolution: WallpaperResolution = .any
    var ratio: WallpaperRatio = .any
    var sorting: WallpaperSorting = .dateAdded
    var tag: String = ""
    var purities: Set<WallpaperPurity>?
    var topRange: WallpaperTopRange = .month
    var color: WallpaperColor?
    var customMinimumResolution: String?
    var randomSeed: String = ""
    var qihooCategory: WallpaperQihooCategory = .all
    var qihooResolution: WallpaperQihooResolution = .any
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

struct WallpaperItem: Codable, Equatable, Hashable, Identifiable, Sendable {
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

protocol WallpaperSourceProviding: Sendable {
    var source: WallpaperSource { get }

    func search(page: Int, filters: WallpaperSearchFilters) async throws -> WallpaperPage
}

enum WallpaperHTTP {
    static let userAgent =
        "Jarvis/\(JarvisAppVersion.shortVersion) (https://github.com/MineonStudio/jarvis-macos; wallpaper)"

    static func request(url: URL, timeout: TimeInterval = 12) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func data(
        for request: URLRequest,
        session: URLSession,
        expectsJSON: Bool = true
    ) async throws -> Data {
        var request = request
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, expectsJSON: expectsJSON)
        return data
    }

    /// Wallhaven's outage page is HTML with HTTP 200. Reject anything that is
    /// not a JSON document before the decoder produces a confusing payload error.
    static func validate(
        response: URLResponse,
        data: Data,
        expectsJSON: Bool = true
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WallpaperAPIError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw WallpaperAPIError.httpStatus(httpResponse.statusCode)
        }
        guard expectsJSON else { return }
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("html") {
            throw WallpaperAPIError.invalidPayload
        }
        let trimmed = data.drop(while: { [0x09, 0x0A, 0x0D, 0x20].contains($0) })
        guard let first = trimmed.first, first == 0x7B || first == 0x5B else {
            throw WallpaperAPIError.invalidPayload
        }
    }
}

final class WallhavenWallpaperSource: WallpaperSourceProviding, @unchecked Sendable {
    let source: WallpaperSource = .wallhaven
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(page: Int, filters: WallpaperSearchFilters) async throws -> WallpaperPage {
        let apiKey = try WallhavenAPIKeyStore.shared.read()
        let url = try Self.searchURL(
            page: page,
            filters: filters,
            includesNSFW: apiKey?.isEmpty == false
        )

        var request = WallpaperHTTP.request(url: url)
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        let data = try await WallpaperHTTP.data(
            for: request,
            session: session
        )
        return try Self.decode(data: data)
    }

    static func searchURL(
        page: Int,
        filters: WallpaperSearchFilters,
        includesNSFW: Bool = false
    ) throws -> URL {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")
        let selectedPurities = filters.purities
            ?? (includesNSFW ? Set(WallpaperPurity.allCases) : Set([.sfw, .sketchy]))
        // Wallhaven purity bits are ordered SFW, Sketchy, NSFW.
        let purities = [WallpaperPurity.sfw, .sketchy, .nsfw]
            .map { selectedPurities.contains($0) ? "1" : "0" }
            .joined()
        components?.queryItems = [
            URLQueryItem(name: "categories", value: "111"),
            URLQueryItem(name: "purity", value: purities == "000" ? "100" : purities),
            URLQueryItem(name: "sorting", value: filters.sorting.apiValue),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "page", value: "\(max(1, page))")
        ]
        if filters.sorting == .toplist {
            components?.queryItems?.append(URLQueryItem(name: "topRange", value: filters.topRange.apiValue))
        }
        let minimumResolution = filters.resolution.minimumResolution
            ?? (filters.resolution == .custom ? normalizedResolution(filters.customMinimumResolution) : nil)
        if let minimumResolution {
            components?.queryItems?.append(
                URLQueryItem(name: "atleast", value: minimumResolution)
            )
        }
        if let ratio = filters.ratio.apiValue {
            components?.queryItems?.append(URLQueryItem(name: "ratios", value: ratio))
        }
        if let color = filters.color {
            components?.queryItems?.append(URLQueryItem(name: "colors", value: color.rawValue))
        }
        let tag = filters.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "q", value: tag))
        }
        let seed = filters.randomSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        if filters.sorting == .random,
           seed.count == 6,
           seed.utf8.allSatisfy({
               (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0)
           })
        {
            components?.queryItems?.append(URLQueryItem(name: "seed", value: seed))
        }
        guard let url = components?.url else {
            throw WallpaperAPIError.invalidURL
        }
        return url
    }

    private static func normalizedResolution(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.lowercased().split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let width = Int(parts[0]), width > 0,
              let height = Int(parts[1]), height > 0
        else {
            return nil
        }
        return "\(width)x\(height)"
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
                // Wallhaven's `large` thumbnail is a fixed landscape crop and
                // cuts portrait wallpapers before they reach the UI. The
                // `original` thumbnail keeps the source aspect ratio; fall
                // back to `large` for older/incomplete API payloads.
                previewURL: remote.thumbs.original ?? remote.thumbs.large,
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
        let original: URL?
    }

    private struct Uploader: Decodable {
        let username: String?
    }
}

final class QihooWallpaperSource: WallpaperSourceProviding, @unchecked Sendable {
    let source: WallpaperSource = .qihoo
    private let session: URLSession

    static let pageSize = 36

    enum Route: Equatable {
        case mixed
        case category(String)
        case search(String)
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(page: Int, filters: WallpaperSearchFilters) async throws -> WallpaperPage {
        switch Self.route(for: filters) {
        case .mixed:
            try await fetchOrder(page: max(1, page), filters: filters)
        case let .category(cid):
            try await fetchCategory(
                cid,
                page: max(1, page),
                count: Self.pageSize,
                filters: filters
            )
        case let .search(query):
            try await fetchSearch(query, page: max(1, page), filters: filters)
        }
    }

    static func route(for filters: WallpaperSearchFilters) -> Route {
        let tag = filters.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty {
            return .search(tag)
        }
        if let cid = filters.qihooCategory.cid {
            return .category(cid)
        }
        return .mixed
    }

    static func orderURL(page: Int, count: Int) throws -> URL {
        var components = URLComponents(string: "http://wallpaper.apc.360.cn/index.php")
        let start = max(0, (page - 1) * count)
        components?.queryItems = [
            URLQueryItem(name: "c", value: "WallPaper"),
            URLQueryItem(name: "a", value: "getAppsByOrder"),
            URLQueryItem(name: "order", value: "create_time"),
            URLQueryItem(name: "start", value: "\(start)"),
            URLQueryItem(name: "count", value: "\(count)"),
            URLQueryItem(name: "from", value: "360chrome")
        ]
        guard let url = components?.url else {
            throw WallpaperAPIError.invalidURL
        }
        return url
    }

    static func categoryURL(cid: String, page: Int, count: Int) throws -> URL {
        var components = URLComponents(string: "http://wallpaper.apc.360.cn/index.php")
        let start = max(0, (page - 1) * count)
        components?.queryItems = [
            URLQueryItem(name: "c", value: "WallPaper"),
            URLQueryItem(name: "a", value: "getAppsByCategory"),
            URLQueryItem(name: "cid", value: cid),
            URLQueryItem(name: "start", value: "\(start)"),
            URLQueryItem(name: "count", value: "\(count)"),
            URLQueryItem(name: "from", value: "360chrome")
        ]
        guard let url = components?.url else {
            throw WallpaperAPIError.invalidURL
        }
        return url
    }

    static func searchURL(query: String, page: Int, count: Int = 24) throws -> URL {
        var components = URLComponents(string: "http://wp.birdpaper.com.cn/intf/search")
        components?.queryItems = [
            URLQueryItem(name: "content", value: query),
            URLQueryItem(name: "pageno", value: "\(max(1, page))"),
            URLQueryItem(name: "count", value: "\(count)")
        ]
        guard let url = components?.url else {
            throw WallpaperAPIError.invalidURL
        }
        return url
    }

    static func httpsURL(from url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
    }

    /// 360's `img_1600_900` is a 16:9 crop. Ask qhimg for a thumbnail that
    /// keeps the wallpaper's real pixel ratio, like Wallhaven's original thumb.
    static func previewURL(from original: URL, width: Int, height: Int) -> URL {
        let source = httpsURL(from: original)
        guard width > 0, height > 0 else { return source }
        let filename = source.lastPathComponent
        guard !filename.isEmpty else { return source }
        let maxEdge = 720
        let scale = min(1, CGFloat(maxEdge) / CGFloat(max(width, height)))
        let previewWidth = max(1, Int((CGFloat(width) * scale).rounded()))
        let previewHeight = max(1, Int((CGFloat(height) * scale).rounded()))
        guard var components = URLComponents(url: source, resolvingAgainstBaseURL: false) else {
            return source
        }
        components.scheme = "https"
        components.path = "/bdm/\(previewWidth)_\(previewHeight)_85/\(filename)"
        return components.url ?? source
    }

    static func decodeCategory(data: Data, page: Int, count: Int, filters: WallpaperSearchFilters) throws -> WallpaperPage {
        let response: CategoryResponse
        do {
            response = try JSONDecoder().decode(CategoryResponse.self, from: data)
        } catch {
            throw WallpaperAPIError.invalidPayload
        }
        guard response.errno.value == "0" else {
            throw WallpaperAPIError.invalidPayload
        }
        let items = (response.data ?? []).compactMap { remote -> WallpaperItem? in
            item(from: remote, filters: filters)
        }
        let total = response.total?.intValue ?? 0
        let start = max(0, (page - 1) * count)
        return WallpaperPage(
            items: items,
            page: page,
            hasNextPage: start + count < total
        )
    }

    static func decodeSearch(data: Data, page: Int, filters: WallpaperSearchFilters) throws -> WallpaperPage {
        let response: SearchResponse
        do {
            response = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw WallpaperAPIError.invalidPayload
        }
        guard response.errno == 0 else {
            throw WallpaperAPIError.invalidPayload
        }
        let items = (response.data?.list ?? []).compactMap { remote -> WallpaperItem? in
            item(from: remote, filters: filters)
        }
        let totalPage = response.data?.totalPage ?? 0
        return WallpaperPage(
            items: items,
            page: page,
            hasNextPage: page < totalPage
        )
    }

    static func matches(_ item: WallpaperItem, filters: WallpaperSearchFilters) -> Bool {
        if item.width <= 0 || item.height <= 0 {
            return filters.qihooResolution == .any
        }
        guard let size = filters.qihooResolution.size else {
            return true
        }
        return item.width == size.width && item.height == size.height
    }

    private func fetchOrder(page: Int, filters: WallpaperSearchFilters) async throws -> WallpaperPage {
        let url = try Self.orderURL(page: page, count: Self.pageSize)
        let data = try await Self.data(from: url, session: session)
        return try Self.decodeCategory(data: data, page: page, count: Self.pageSize, filters: filters)
    }

    private func fetchCategory(
        _ cid: String,
        page: Int,
        count: Int,
        filters: WallpaperSearchFilters
    ) async throws -> WallpaperPage {
        try await Self.loadCategory(cid, page: page, count: count, filters: filters, session: session)
    }

    private func fetchSearch(
        _ query: String,
        page: Int,
        filters: WallpaperSearchFilters
    ) async throws -> WallpaperPage {
        let url = try Self.searchURL(query: query, page: page, count: Self.pageSize)
        let data = try await Self.data(from: url, session: session)
        return try Self.decodeSearch(data: data, page: page, filters: filters)
    }

    private static func loadCategory(
        _ cid: String,
        page: Int,
        count: Int,
        filters: WallpaperSearchFilters,
        session: URLSession
    ) async throws -> WallpaperPage {
        let url = try categoryURL(cid: cid, page: page, count: count)
        let data = try await data(from: url, session: session)
        return try decodeCategory(data: data, page: page, count: count, filters: filters)
    }

    private static func data(from url: URL, session: URLSession) async throws -> Data {
        var lastError: Error?
        for _ in 0 ..< 2 {
            do {
                var request = WallpaperHTTP.request(url: url, timeout: 8)
                request.setValue(
                    "Mozilla/5.0 Jarvis/\(JarvisAppVersion.shortVersion)",
                    forHTTPHeaderField: "User-Agent"
                )
                return try await WallpaperHTTP.data(for: request, session: session)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                lastError = error
            }
        }
        throw lastError ?? WallpaperAPIError.invalidResponse
    }

    private static func item(from remote: CategoryItem, filters: WallpaperSearchFilters) -> WallpaperItem? {
        let originalURL = httpsURL(from: remote.url)
        let dimensions = parseResolution(remote.resolution)
        let previewURL = previewURL(
            from: originalURL,
            width: dimensions?.width ?? 0,
            height: dimensions?.height ?? 0
        )
        let item = WallpaperItem(
            id: "qihoo:\(remote.id.value)",
            source: .qihoo,
            sourceID: remote.id.value,
            title: title(utag: remote.utag, tag: remote.tag, fallback: remote.id.value),
            previewURL: previewURL,
            originalURL: originalURL,
            sourcePageURL: nil,
            authorName: nil,
            authorURL: nil,
            width: dimensions?.width ?? 0,
            height: dimensions?.height ?? 0,
            fileExtension: originalURL.pathExtension.isEmpty ? "jpg" : originalURL.pathExtension,
            licenseName: "版权以原作者页面为准",
            licenseURL: nil,
            isFavorite: false,
            localFileName: nil
        )
        return matches(item, filters: filters) ? item : nil
    }

    private static func item(from remote: SearchItem, filters: WallpaperSearchFilters) -> WallpaperItem? {
        let originalURL = httpsURL(from: remote.url)
        let item = WallpaperItem(
            id: "qihoo:\(remote.id)",
            source: .qihoo,
            sourceID: remote.id,
            title: title(utag: remote.tag, tag: remote.category, fallback: remote.id),
            previewURL: originalURL,
            originalURL: originalURL,
            sourcePageURL: nil,
            authorName: remote.author,
            authorURL: nil,
            width: 0,
            height: 0,
            fileExtension: originalURL.pathExtension.isEmpty ? "jpg" : originalURL.pathExtension,
            licenseName: "版权以原作者页面为准",
            licenseURL: nil,
            isFavorite: false,
            localFileName: nil
        )
        return matches(item, filters: filters) ? item : nil
    }

    private static func title(utag: String?, tag: String?, fallback: String) -> String {
        let cleanedUtag = utag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanedUtag.isEmpty {
            return cleanedUtag
        }
        let cleanedTag = tag?
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanedTag.isEmpty {
            return cleanedTag
        }
        return "壁纸 \(fallback)"
    }

    static func parseResolution(_ value: String?) -> (width: Int, height: Int)? {
        guard let value else { return nil }
        let parts = value.lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]),
              width > 0,
              height > 0
        else {
            return nil
        }
        return (width, height)
    }

    private struct CategoryResponse: Decodable {
        let errno: FlexibleString
        let total: FlexibleString?
        let data: [CategoryItem]?
    }

    private struct CategoryItem: Decodable {
        let id: FlexibleString
        let url: URL
        let resolution: String?
        let tag: String?
        let utag: String?
    }

    private struct SearchResponse: Decodable {
        let errno: Int
        let data: SearchData?
    }

    private struct SearchData: Decodable {
        let list: [SearchItem]?
        let totalPage: Int?

        enum CodingKeys: String, CodingKey {
            case list
            case totalPage = "total_page"
        }
    }

    private struct SearchItem: Decodable {
        let id: String
        let author: String?
        let category: String?
        let tag: String?
        let url: URL
    }

    struct FlexibleString: Decodable {
        let value: String

        var intValue: Int {
            Int(value) ?? 0
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                value = string
            } else if let int = try? container.decode(Int.self) {
                value = String(int)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected string or int"
                )
            }
        }
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
    private let file: JarvisJSONFile<[WallpaperItem]>

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let directory = JarvisAppDirectory.url("Wallpapers", fileManager: fileManager)
        directoryURL = directory
        file = JarvisJSONFile(
            directoryURL: directory,
            fileName: "metadata.json",
            logDomain: "wallpaper.metadata",
            fileManager: fileManager
        )
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        file = JarvisJSONFile(
            directoryURL: directoryURL,
            fileName: "metadata.json",
            logDomain: "wallpaper.metadata",
            fileManager: fileManager
        )
    }

    func load() -> [WallpaperItem] {
        storedItems().filter { localURL(for: $0) != nil }
    }

    func loadFavorites() -> [WallpaperItem] {
        storedItems().filter(\.isFavorite)
    }

    private func storedItems() -> [WallpaperItem] {
        file.readOrDefault([])
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

        var items = try itemsForWriting()
        items.removeAll { $0.id == item.id }
        try file.writeOrThrow(items)
    }

    func upsert(_ item: WallpaperItem) throws {
        var items = try itemsForWriting()
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
        try file.writeOrThrow(items)
    }

    private func itemsForWriting() throws -> [WallpaperItem] {
        try file.readForWriting(default: [])
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

final class WallpaperDownloadService: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "wallhaven.cc"
            || host.hasSuffix(".wallhaven.cc")
            || host == "qhimg.com"
            || host.hasSuffix(".qhimg.com")
            || host.hasSuffix(".shanhutech.cn")
            || host == "upload.wikimedia.org"
            || host.hasSuffix(".wikimedia.org")
            || host.hasSuffix(".wikipedia.org")
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
///
/// `wallpaperIndexURL` points at a system preferences file, not at our own
/// storage, so it is deliberately written with a plain atomic write instead of
/// `JarvisProtectedStorage.write`: the 0600 permission that helper applies
/// belongs to Jarvis-owned files and must not be imposed on system records.
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

    @Published var selectedSource: WallpaperSource
    @Published var selectedResolution: WallpaperResolution = .any
    @Published var selectedRatio: WallpaperRatio = .any
    @Published var selectedSorting: WallpaperSorting = .dateAdded
    @Published var selectedPurityPreset: WallpaperPurityPreset = .automatic
    @Published var selectedTopRange: WallpaperTopRange = .month
    @Published var selectedColor: WallpaperColor?
    @Published var customMinimumResolution = ""
    @Published var randomSeed = ""
    @Published var selectedQihooCategory: WallpaperQihooCategory = .all
    @Published var selectedQihooResolution: WallpaperQihooResolution = .any
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
    private let wallhavenSource: any WallpaperSourceProviding
    private let qihooSource: any WallpaperSourceProviding
    private let downloader: WallpaperDownloadService
    private let wallpaperSystemService: WallpaperSystemService
    private var currentPage = 1
    private var currentFilters = WallpaperSearchFilters()
    private var bufferedItems: [WallpaperItem] = []
    private var canFetchMorePages = false

    init(
        store: WallpaperStore = WallpaperStore(),
        wallhavenSource: any WallpaperSourceProviding = WallhavenWallpaperSource(),
        qihooSource: any WallpaperSourceProviding = QihooWallpaperSource(),
        downloader: WallpaperDownloadService = WallpaperDownloadService(),
        desktopWallpaperService: DesktopWallpaperService? = nil,
        wallpaperSystemService: WallpaperSystemService? = nil,
        initialSelectedSource: WallpaperSource? = nil
    ) {
        selectedSource = initialSelectedSource
            ?? WallpaperSourcePreferences.enabledSources(
                from: UserDefaults.standard.string(forKey: WallpaperSourcePreferences.storageKey)
                    ?? WallpaperSourcePreferences.defaultStorageValue
            ).first
            ?? .wallhaven
        self.store = store
        self.wallhavenSource = wallhavenSource
        self.qihooSource = qihooSource
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
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        loadMoreErrorMessage = nil
        currentPage = 1
        currentFilters = currentSearchFilters
        defer {
            if generation == searchGeneration {
                isLoading = false
            }
        }

        do {
            var page = try await fetchPage(page: 1, filters: currentFilters)
            var loadedItems = mergeWithSavedItems(page.items)

            while loadedItems.count < Self.initialDisplayCount, page.hasNextPage {
                guard generation == searchGeneration else { return }
                page = try await fetchPage(page: page.page + 1, filters: currentFilters)
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
        defer {
            if generation == searchGeneration {
                isLoadingMore = false
            }
        }

        do {
            var nextItems = Array(bufferedItems.prefix(Self.loadMoreDisplayCount))
            var nextBufferedItems = Array(bufferedItems.dropFirst(nextItems.count))
            var nextPage = currentPage
            var nextCanFetchMorePages = canFetchMorePages

            while nextItems.count < Self.loadMoreDisplayCount, nextCanFetchMorePages {
                let page = try await fetchPage(
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
            errorMessage = JarvisFeedbackCopy.favoriteFailed
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
            errorMessage = JarvisFeedbackCopy.deleteFailed
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
        guard !downloadingIDs.contains(item.id) else { return JarvisFeedbackCopy.wallpaperBusy }

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
                return JarvisFeedbackCopy.wallpaperFileUnavailable
            }
            try wallpaperSystemService.apply(imageURL: localURL, target: target)
            appliedWallpaperID = savedItem.id
            refreshLibrary()
            return JarvisFeedbackCopy.applied
        } catch {
            return JarvisFeedbackCopy.applyFailed
        }
    }

    private var currentSearchFilters: WallpaperSearchFilters {
        WallpaperSearchFilters(
            resolution: selectedResolution,
            ratio: selectedRatio,
            sorting: selectedSorting,
            tag: selectedTag,
            purities: selectedPurityPreset.purities,
            topRange: selectedTopRange,
            color: selectedColor,
            customMinimumResolution: customMinimumResolution,
            randomSeed: randomSeed,
            qihooCategory: selectedQihooCategory,
            qihooResolution: selectedQihooResolution
        )
    }

    private func fetchPage(page: Int, filters: WallpaperSearchFilters) async throws -> WallpaperPage {
        try await sourceProvider(for: selectedSource).search(page: page, filters: filters)
    }

    private func sourceProvider(for source: WallpaperSource) -> any WallpaperSourceProviding {
        switch source {
        case .qihoo:
            qihooSource
        case .wallhaven, .wikimedia, .local:
            wallhavenSource
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

enum WallpaperImageLoader {
    private static let imageCache = JarvisThreadSafeImageCache(
        countLimit: 48,
        totalCostLimit: 64 * 1024 * 1024
    )

    static func purgeCache() {
        imageCache.removeAllObjects()
    }

    static func loadOriginal(url: URL) async -> NSImage? {
        let data: Data
        do {
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                data = try await WallpaperHTTP.data(
                    for: WallpaperHTTP.request(url: url, timeout: 45),
                    session: .shared,
                    expectsJSON: false
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

    static func load(url: URL, maxPixelSize: Int = 512) async -> NSImage? {
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
        imageCache.setObject(
            image,
            forKey: cacheKey,
            cost: max(1, cgImage.bytesPerRow * cgImage.height)
        )
        return image
    }
}
