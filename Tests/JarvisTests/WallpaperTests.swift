import AppKit
@testable import Jarvis
import XCTest

final class WallpaperTests: XCTestCase {
    func testWallpaperSourceIsWallhavenAndKeepsLegacyLocalRecordsDecodable() {
        XCTAssertEqual(WallpaperSource.wallhaven.title, "Wallhaven")
        XCTAssertEqual(WallpaperSource.qihoo.title, "360壁纸")
        XCTAssertEqual(WallpaperSource.wikimedia.title, "Wikimedia")
        XCTAssertEqual(WallpaperSource.local.title, "本地")
        XCTAssertEqual(WallpaperSource.onlineGalleryCases, [.wallhaven, .qihoo])
    }

    func testWallpaperFiltersExposeWallhavenResolutionOptions() {
        XCTAssertEqual(WallpaperResolution.hd.minimumResolution, "1280x720")
        XCTAssertEqual(WallpaperResolution.fullHD.minimumResolution, "1920x1080")
        XCTAssertEqual(WallpaperResolution.wuxga.minimumResolution, "1920x1200")
        XCTAssertEqual(WallpaperResolution.uwfhd.minimumResolution, "2560x1080")
        XCTAssertEqual(WallpaperResolution.qHD.minimumResolution, "2560x1440")
        XCTAssertEqual(WallpaperResolution.uwqhd.minimumResolution, "3440x1440")
        XCTAssertEqual(WallpaperResolution.uhd.minimumResolution, "3840x2160")
        XCTAssertEqual(WallpaperResolution.fiveK.minimumResolution, "5120x2880")
        XCTAssertEqual(WallpaperResolution.superUltrawide.minimumResolution, "5120x1440")
        XCTAssertEqual(WallpaperResolution.eightK.minimumResolution, "7680x4320")
        XCTAssertNil(WallpaperResolution.any.minimumResolution)
    }

    func testWallpaperRatioAndTagFiltersExposeWallhavenQueries() {
        XCTAssertEqual(WallpaperRatio.landscape.apiValue, "16x9,16x10,21x9,32x9,48x9,3x2,4x3,5x4")
        XCTAssertEqual(WallpaperRatio.portrait.apiValue, "9x16,10x16,9x18")
        XCTAssertEqual(WallpaperRatio.square.apiValue, "1x1")
        XCTAssertNil(WallpaperRatio.any.apiValue)
        XCTAssertTrue(WallpaperTags.popular.contains { $0.query == "landscape" })
        XCTAssertTrue(WallpaperTags.popular.contains { $0.query == "space" })
        XCTAssertFalse(WallpaperTags.popular.contains { $0.query == "美女" })
        XCTAssertEqual(
            WallpaperSorting.allCases.map(\.apiValue),
            ["toplist", "date_added", "relevance", "views", "favorites", "random"]
        )
    }

    @MainActor
    func testWallpaperDefaultsUseLatestSortingAndExpandedInitialBatch() {
        let filters = WallpaperSearchFilters()

        XCTAssertEqual(filters.sorting, .dateAdded)
        XCTAssertEqual(filters.sorting.title, "最新")
        XCTAssertEqual(filters.qihooCategory, .all)
        XCTAssertEqual(WallpaperViewModel().selectedSource, .wallhaven)
        XCTAssertEqual(WallpaperViewModel.initialDisplayCount, 36)
    }

    func testWallpaperLibraryModesExposeOnlineDownloadedAndFavorites() {
        XCTAssertEqual(
            WallpaperLibraryMode.allCases.map(\.title),
            ["在线图库", "已下载", "我的收藏"]
        )
    }

    func testWallpaperDownloadsOnlyAllowWallhavenHTTPSHosts() throws {
        XCTAssertTrue(
            try WallpaperDownloadService.isAllowedDownloadURL(
                XCTUnwrap(URL(string: "https://w.wallhaven.cc/full/ab/wallhaven-abc.png"))
            )
        )
        XCTAssertTrue(
            try WallpaperDownloadService.isAllowedDownloadURL(
                XCTUnwrap(URL(string: "https://wallhaven.cc/image.png"))
            )
        )
        XCTAssertTrue(
            try WallpaperDownloadService.isAllowedDownloadURL(
                XCTUnwrap(URL(string: "https://p3.qhimg.com/bdr/__85/test.jpg"))
            )
        )
        XCTAssertTrue(
            try WallpaperDownloadService.isAllowedDownloadURL(
                XCTUnwrap(URL(string: "https://cdn-hsyq-static.shanhutech.cn/bizhi/test.jpg"))
            )
        )
        XCTAssertTrue(
            try WallpaperDownloadService.isAllowedDownloadURL(
                XCTUnwrap(URL(string: "https://upload.wikimedia.org/wikipedia/commons/a/ab/Test.jpg"))
            )
        )
        XCTAssertFalse(
            try WallpaperDownloadService.isAllowedDownloadURL(
                XCTUnwrap(URL(string: "http://w.wallhaven.cc/full/ab/wallhaven-abc.png"))
            )
        )
        XCTAssertFalse(
            try WallpaperDownloadService.isAllowedDownloadURL(
                XCTUnwrap(URL(string: "https://evil.example/payload.png"))
            )
        )
    }

    func testWallpaperHTTPRejectsHTMLOutagePagesEvenWithHTTP200() throws {
        let html = Data("<!DOCTYPE html><title>wallhaven.cc Status</title>".utf8)
        let response = try HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://wallhaven.cc/api/v1/search")),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )
        XCTAssertThrowsError(
            try WallpaperHTTP.validate(response: XCTUnwrap(response), data: html)
        ) { error in
            XCTAssertEqual(error as? WallpaperAPIError, .invalidPayload)
        }
    }

    func testWallpaperHTTPAcceptsJSONPayloads() throws {
        let json = Data(#"{"data":[]}"#.utf8)
        let response = try HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://wallhaven.cc/api/v1/search")),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )
        XCTAssertNoThrow(
            try WallpaperHTTP.validate(response: XCTUnwrap(response), data: json)
        )
    }

    func testQihooEmptyGalleryUsesASingleNewestList() throws {
        XCTAssertEqual(QihooWallpaperSource.route(for: WallpaperSearchFilters()), .mixed)
        let url = try QihooWallpaperSource.orderURL(page: 1, count: 36)
        let query = try Dictionary(
            uniqueKeysWithValues: XCTUnwrap(
                URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            ).map { ($0.name, $0.value) }
        )
        XCTAssertEqual(url.host, "wallpaper.apc.360.cn")
        XCTAssertEqual(query["a"], "getAppsByOrder")
        XCTAssertEqual(query["order"], "create_time")
        XCTAssertEqual(query["count"], "36")
        XCTAssertEqual(WallpaperQihooCategory.girls.title, "美女模特")
        XCTAssertEqual(WallpaperQihooCategory.girls.cid, "6")
        XCTAssertNil(WallpaperQihooCategory.all.cid)
    }

    func testQihooRoutesCategoryAndSearchIndependently() throws {
        XCTAssertEqual(
            QihooWallpaperSource.route(for: WallpaperSearchFilters(qihooCategory: .girls)),
            .category("6")
        )
        XCTAssertEqual(
            QihooWallpaperSource.route(for: WallpaperSearchFilters(qihooCategory: .anime)),
            .category("26")
        )
        XCTAssertEqual(
            QihooWallpaperSource.route(for: WallpaperSearchFilters(tag: "赛博朋克")),
            .search("赛博朋克")
        )
        XCTAssertEqual(
            QihooWallpaperSource.route(
                for: WallpaperSearchFilters(tag: "赛博朋克", qihooCategory: .girls)
            ),
            .search("赛博朋克")
        )

        let searchURL = try QihooWallpaperSource.searchURL(query: "赛博朋克", page: 2, count: 24)
        let searchQuery = try Dictionary(
            uniqueKeysWithValues: XCTUnwrap(
                URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?.queryItems
            ).map { ($0.name, $0.value) }
        )
        XCTAssertEqual(searchURL.host, "wp.birdpaper.com.cn")
        XCTAssertEqual(searchQuery["content"], "赛博朋克")
        XCTAssertEqual(searchQuery["pageno"], "2")

        let categoryURL = try QihooWallpaperSource.categoryURL(cid: "6", page: 3, count: 8)
        let categoryQuery = try Dictionary(
            uniqueKeysWithValues: XCTUnwrap(
                URLComponents(url: categoryURL, resolvingAgainstBaseURL: false)?.queryItems
            ).map { ($0.name, $0.value) }
        )
        XCTAssertEqual(categoryURL.host, "wallpaper.apc.360.cn")
        XCTAssertEqual(categoryQuery["cid"], "6")
        XCTAssertEqual(categoryQuery["start"], "16")
        XCTAssertEqual(categoryQuery["count"], "8")
    }

    func testQihooRewritesHTTPImageURLsToHTTPS() throws {
        let httpURL = try XCTUnwrap(URL(string: "http://p3.qhimg.com/bdr/__85/test.jpg"))
        XCTAssertEqual(
            QihooWallpaperSource.httpsURL(from: httpURL).absoluteString,
            "https://p3.qhimg.com/bdr/__85/test.jpg"
        )
    }

    func testQihooDecodesCategoryItemsAndRewritesHTTPS() throws {
        let data = Data(
            """
            {
              "errno": "0",
              "total": "40",
              "data": [
                {
                  "id": "2054151",
                  "url": "http://p3.qhimg.com/bdr/__85/girl.jpg",
                  "url_thumb": "http://p3.qhimg.com/bdr/__85/girl.jpg",
                  "img_1600_900": "http://p3.qhimg.com/bdm/1600_900_85/girl.jpg",
                  "resolution": "3840x2160",
                  "utag": "清纯",
                  "tag": "_美女模特_"
                },
                {
                  "id": "1",
                  "url": "http://p3.qhimg.com/bdr/__85/small.jpg",
                  "resolution": "800x600",
                  "utag": "small"
                }
              ]
            }
            """.utf8
        )

        let unfiltered = try QihooWallpaperSource.decodeCategory(
            data: data,
            page: 1,
            count: 24,
            filters: WallpaperSearchFilters()
        )
        XCTAssertEqual(unfiltered.items.count, 2)

        let page = try QihooWallpaperSource.decodeCategory(
            data: data,
            page: 1,
            count: 24,
            filters: WallpaperSearchFilters(qihooResolution: .uhd)
        )
        XCTAssertEqual(page.items.count, 1)
        let item = try XCTUnwrap(page.items.first)
        XCTAssertEqual(item.source, .qihoo)
        XCTAssertEqual(item.id, "qihoo:2054151")
        XCTAssertEqual(item.title, "清纯")
        XCTAssertEqual(item.resolutionDescription, "3840 × 2160")
        XCTAssertEqual(
            item.originalURL.absoluteString,
            "https://p3.qhimg.com/bdr/__85/girl.jpg"
        )
        XCTAssertEqual(
            item.previewURL.absoluteString,
            "https://p3.qhimg.com/bdm/720_405_85/girl.jpg"
        )
        XCTAssertFalse(item.previewURL.absoluteString.contains("1600_900"))
        XCTAssertTrue(page.hasNextPage)
    }

    func testQihooPreviewURLKeepsTheSourceAspectRatio() throws {
        let original = try XCTUnwrap(URL(string: "http://p3.qhimg.com/bdr/__85/wide.jpg"))
        XCTAssertEqual(
            QihooWallpaperSource.previewURL(from: original, width: 1920, height: 1200).absoluteString,
            "https://p3.qhimg.com/bdm/720_450_85/wide.jpg"
        )
        XCTAssertEqual(
            QihooWallpaperSource.previewURL(from: original, width: 3840, height: 2560).absoluteString,
            "https://p3.qhimg.com/bdm/720_480_85/wide.jpg"
        )
    }

    func testQihooMatchesExactCatalogResolutions() throws {
        let imageURL = try XCTUnwrap(URL(string: "https://p3.qhimg.com/4k.jpg"))
        let landscape4K = WallpaperItem(
            id: "qihoo:4k",
            source: .qihoo,
            sourceID: "4k",
            title: "4K",
            previewURL: imageURL,
            originalURL: imageURL,
            sourcePageURL: nil,
            authorName: nil,
            authorURL: nil,
            width: 3840,
            height: 2160,
            fileExtension: "jpg",
            licenseName: nil,
            licenseURL: nil,
            isFavorite: false,
            localFileName: nil
        )
        XCTAssertTrue(QihooWallpaperSource.matches(landscape4K, filters: WallpaperSearchFilters()))
        XCTAssertTrue(
            QihooWallpaperSource.matches(landscape4K, filters: WallpaperSearchFilters(qihooResolution: .uhd))
        )
        XCTAssertFalse(
            QihooWallpaperSource.matches(
                landscape4K,
                filters: WallpaperSearchFilters(qihooResolution: .fiveK)
            )
        )
        XCTAssertEqual(
            WallpaperQihooResolution.allCases.map(\.title),
            [
                "不限分辨率",
                "1920 × 1080",
                "1920 × 1200",
                "2560 × 1440",
                "2560 × 1600",
                "2880 × 1800",
                "3840 × 2160",
                "4096 × 2304",
                "5120 × 2880"
            ]
        )
    }

    func testQihooDecodesBirdpaperSearchResults() throws {
        let data = Data(
            """
            {
              "errno": 0,
              "data": {
                "total_count": 70,
                "total_page": 3,
                "pageno": 1,
                "count": 1,
                "list": [
                  {
                    "id": "2066652",
                    "author": "潇",
                    "category": "游戏壁纸",
                    "tag": "赛博朋克,边缘行者",
                    "url": "http://cdn-hsyq-static.shanhutech.cn/bizhi/cyberpunk.jpg",
                    "class_id": "5"
                  }
                ]
              }
            }
            """.utf8
        )

        let page = try QihooWallpaperSource.decodeSearch(
            data: data,
            page: 1,
            filters: WallpaperSearchFilters(tag: "cyberpunk")
        )
        let item = try XCTUnwrap(page.items.first)
        XCTAssertEqual(item.id, "qihoo:2066652")
        XCTAssertEqual(item.authorName, "潇")
        XCTAssertEqual(
            item.originalURL.absoluteString,
            "https://cdn-hsyq-static.shanhutech.cn/bizhi/cyberpunk.jpg"
        )
        XCTAssertTrue(page.hasNextPage)
    }

    @MainActor
    func testWallpaperRefreshUsesTheSelectedSourceOnly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-wallpaper-fallback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = try WallpaperItem(
            id: "qihoo:fallback",
            source: .qihoo,
            sourceID: "fallback",
            title: "Fallback",
            previewURL: XCTUnwrap(URL(string: "https://p3.qhimg.com/bdr/__85/fallback.jpg")),
            originalURL: XCTUnwrap(URL(string: "https://p3.qhimg.com/bdr/__85/fallback.jpg")),
            sourcePageURL: nil,
            authorName: nil,
            authorURL: nil,
            width: 1920,
            height: 1080,
            fileExtension: "jpg",
            licenseName: nil,
            licenseURL: nil,
            isFavorite: false,
            localFileName: nil
        )
        let model = WallpaperViewModel(
            store: WallpaperStore(directoryURL: directory),
            wallhavenSource: FailingWallpaperSource(),
            qihooSource: StubWallpaperSource(item: item)
        )

        await model.refresh()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.items.isEmpty)

        model.selectedSource = .qihoo
        await model.refresh()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.items.map(\.id), ["qihoo:fallback"])
    }

    func testWallpaperSkillUsesDesktopWallpaperName() {
        XCTAssertEqual(SkillID.wallpaper.title, "桌面壁纸技能")
        XCTAssertEqual(SkillID.wallpaper.navigationTitle, "桌面壁纸")
    }

    func testWallpaperSearchFiltersDefaultToUnrestrictedValues() {
        let filters = WallpaperSearchFilters()

        XCTAssertEqual(filters.resolution, .any)
        XCTAssertEqual(filters.ratio, .any)
        XCTAssertEqual(filters.resolution.title, "不限分辨率")
        XCTAssertEqual(filters.ratio.title, "不限比例")
    }

    func testWallhavenSearchURLContainsAllSelectedFilters() throws {
        let filters = WallpaperSearchFilters(
            resolution: .uwqhd,
            ratio: .twentyOneByNine,
            sorting: .dateAdded,
            tag: "cyberpunk"
        )
        let url = try WallhavenWallpaperSource.searchURL(page: 3, filters: filters)
        let queryItems = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

        XCTAssertEqual(query["categories"], "111")
        XCTAssertEqual(query["purity"], "110")
        XCTAssertEqual(query["atleast"], "3440x1440")
        XCTAssertEqual(query["ratios"], "21x9")
        XCTAssertEqual(query["sorting"], "date_added")
        XCTAssertEqual(query["q"], "cyberpunk")
        XCTAssertEqual(query["page"], "3")
    }

    func testWallpaperSettingTargetsHaveExpectedLockScreenSemantics() {
        XCTAssertFalse(WallpaperSettingTarget.desktop.requiresLockScreen)
        XCTAssertTrue(WallpaperSettingTarget.lockScreen.requiresLockScreen)
        XCTAssertTrue(WallpaperSettingTarget.both.requiresLockScreen)
        XCTAssertEqual(
            WallpaperSettingTarget.allCases.map(\.title),
            ["仅桌面壁纸", "仅锁屏壁纸", "桌面 + 锁屏"]
        )
    }

    func testWallhavenResponseDecodesSafeWallpaperMetadata() throws {
        let data = Data(
            """
            {
              "data": [
                {
                  "id": "abc123",
                  "url": "https://wallhaven.cc/w/abc123",
                  "path": "https://w.wallhaven.cc/ab/wallhaven-abc123.jpg",
                  "dimension_x": 2560,
                  "dimension_y": 1440,
                  "thumbs": {
                    "large": "https://th.wallhaven.cc/lg/ab/abc123.jpg",
                    "original": "https://th.wallhaven.cc/orig/ab/abc123.jpg"
                  },
                  "uploader": {
                    "username": "tester"
                  }
                }
              ],
              "meta": {
                "current_page": 1,
                "last_page": 2
              }
            }
            """.utf8
        )

        let page = try WallhavenWallpaperSource.decode(data: data)
        let item = try XCTUnwrap(page.items.first)

        XCTAssertEqual(item.id, "wallhaven:abc123")
        XCTAssertEqual(item.authorName, "tester")
        XCTAssertEqual(item.resolutionDescription, "2560 × 1440")
        XCTAssertEqual(item.sourcePageURL?.absoluteString, "https://wallhaven.cc/w/abc123")
        XCTAssertEqual(
            item.previewURL.absoluteString,
            "https://th.wallhaven.cc/orig/ab/abc123.jpg"
        )
        XCTAssertTrue(page.hasNextPage)
    }

    func testWallpaperStoreCopiesValidImagesAndRejectsUnsafeMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-wallpaper-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WallpaperStore(directoryURL: directory)
        let sourceURL = directory.appendingPathComponent("source.png")
        try makeTestPNG().write(to: sourceURL)

        let item = WallpaperItem(
            id: "wallhaven:test",
            source: .wallhaven,
            sourceID: "test",
            title: "Test wallpaper",
            previewURL: sourceURL,
            originalURL: sourceURL,
            sourcePageURL: nil,
            authorName: nil,
            authorURL: nil,
            width: 4,
            height: 2,
            fileExtension: "png",
            licenseName: nil,
            licenseURL: nil,
            isFavorite: false,
            localFileName: nil
        )
        let savedItem = try store.save(downloadedFileURL: sourceURL, for: item)
        let storedURL = try XCTUnwrap(store.localURL(for: savedItem))

        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(store.load().map(\.id), [item.id])

        var unsafeItem = savedItem
        unsafeItem.localFileName = "wallpaper-../../outside.png"
        XCTAssertNil(store.localURL(for: unsafeItem))
    }

    func testWallpaperStorePersistsFavoriteWithoutDownloadingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-wallpaper-favorite-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WallpaperStore(directoryURL: directory)
        let remoteURL = try XCTUnwrap(URL(string: "https://w.wallhaven.cc/test.jpg"))
        let item = WallpaperItem(
            id: "wallhaven:favorite-test",
            source: .wallhaven,
            sourceID: "favorite-test",
            title: "Favorite test",
            previewURL: remoteURL,
            originalURL: remoteURL,
            sourcePageURL: nil,
            authorName: nil,
            authorURL: nil,
            width: 2560,
            height: 1440,
            fileExtension: "jpg",
            licenseName: nil,
            licenseURL: nil,
            isFavorite: true,
            localFileName: nil
        )

        try store.upsert(item)
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertEqual(store.loadFavorites().map(\.id), [item.id])

        var unliked = item
        unliked.isFavorite = false
        try store.upsert(unliked)
        XCTAssertTrue(store.loadFavorites().isEmpty)
    }

    /// 元数据读不出来时必须留证据，不能让随后的 upsert 用一个新数组把它整份覆盖掉。
    func testWallpaperStoreQuarantinesUnreadableMetadataInsteadOfOverwritingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-wallpaper-corrupt-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WallpaperStore(directoryURL: directory)
        let metadataURL = directory.appendingPathComponent("metadata.json")
        let corruptPayload = Data("{ not json at all".utf8)
        try corruptPayload.write(to: metadataURL)

        XCTAssertTrue(store.loadFavorites().isEmpty)

        // 损坏文件被挪到一边留证，原路径腾空，后续写入不再覆盖未知内容。
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let quarantined = try XCTUnwrap(
            entries.first { $0.lastPathComponent.hasPrefix("metadata.corrupt-") }
        )
        XCTAssertEqual(try Data(contentsOf: quarantined), corruptPayload)

        let remoteURL = try XCTUnwrap(URL(string: "https://w.wallhaven.cc/corrupt-test.jpg"))
        try store.upsert(WallpaperItem(
            id: "wallhaven:corrupt-test",
            source: .wallhaven,
            sourceID: "corrupt-test",
            title: "Corrupt test",
            previewURL: remoteURL,
            originalURL: remoteURL,
            sourcePageURL: nil,
            authorName: nil,
            authorURL: nil,
            width: 2560,
            height: 1440,
            fileExtension: "jpg",
            licenseName: nil,
            licenseURL: nil,
            isFavorite: true,
            localFileName: nil
        ))

        // 收藏照常可用，留证的那份文件也不受影响。
        XCTAssertEqual(store.loadFavorites().map(\.id), ["wallhaven:corrupt-test"])
        XCTAssertEqual(try Data(contentsOf: quarantined), corruptPayload)
    }

    /// 损坏文件挪不动时必须拒绝写入：照常写下去就会把它整份覆盖，正是要修的 bug。
    func testWallpaperStoreRefusesToWriteWhenUnreadableMetadataCannotBeQuarantined() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-wallpaper-quarantine-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let metadataURL = directory.appendingPathComponent("metadata.json")
        let corruptPayload = Data("{ not json at all".utf8)
        try corruptPayload.write(to: metadataURL)

        let store = WallpaperStore(directoryURL: directory, fileManager: MoveFailingFileManager())
        XCTAssertTrue(store.loadFavorites().isEmpty)

        let item = try WallpaperItem(
            id: "wallhaven:unreadable",
            source: .wallhaven,
            sourceID: "unreadable",
            title: "Unreadable",
            previewURL: XCTUnwrap(URL(string: "https://w.wallhaven.cc/unreadable.jpg")),
            originalURL: XCTUnwrap(URL(string: "https://w.wallhaven.cc/unreadable.jpg")),
            sourcePageURL: nil,
            authorName: nil,
            authorURL: nil,
            width: 2560,
            height: 1440,
            fileExtension: "jpg",
            licenseName: nil,
            licenseURL: nil,
            isFavorite: true,
            localFileName: nil
        )

        XCTAssertThrowsError(try store.upsert(item)) { error in
            XCTAssertEqual(error as? JarvisJSONFileError, .unreadable)
        }
        XCTAssertThrowsError(try store.delete(item)) { error in
            XCTAssertEqual(error as? JarvisJSONFileError, .unreadable)
        }

        // 原文件原样留着，现场没丢。
        XCTAssertEqual(try Data(contentsOf: metadataURL), corruptPayload)
    }

    /// 写盘失败必须让视图模型知道：`toggleFavorite` 只靠 catch 决定要不要提示
    /// 「收藏失败」，静默报告成功会让星星闪一下又弹回去。
    func testWallpaperStoreReportsFailedSaves() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-wallpaper-readonly-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let store = WallpaperStore(directoryURL: directory)
        let remoteURL = try XCTUnwrap(URL(string: "https://w.wallhaven.cc/readonly.jpg"))
        func makeItem(id: String) -> WallpaperItem {
            WallpaperItem(
                id: id,
                source: .wallhaven,
                sourceID: id,
                title: id,
                previewURL: remoteURL,
                originalURL: remoteURL,
                sourcePageURL: nil,
                authorName: nil,
                authorURL: nil,
                width: 2560,
                height: 1440,
                fileExtension: "jpg",
                licenseName: nil,
                licenseURL: nil,
                isFavorite: true,
                localFileName: nil
            )
        }

        // 先留下一条能读出来的元数据，再让目录只读。
        try store.upsert(makeItem(id: "wallhaven:first"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        XCTAssertThrowsError(try store.upsert(makeItem(id: "wallhaven:second")), "写入失败没有报告")
        XCTAssertThrowsError(try store.delete(makeItem(id: "wallhaven:first")), "删除失败没有报告")
    }

    func testWallpaperStoreWritesMetadataWithOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-wallpaper-permission-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WallpaperStore(directoryURL: directory)
        let remoteURL = try XCTUnwrap(URL(string: "https://w.wallhaven.cc/permission-test.jpg"))
        try store.upsert(WallpaperItem(
            id: "wallhaven:permission-test",
            source: .wallhaven,
            sourceID: "permission-test",
            title: "Permission test",
            previewURL: remoteURL,
            originalURL: remoteURL,
            sourcePageURL: nil,
            authorName: nil,
            authorURL: nil,
            width: 2560,
            height: 1440,
            fileExtension: "jpg",
            licenseName: nil,
            licenseURL: nil,
            isFavorite: true,
            localFileName: nil
        ))

        let metadataURL = directory.appendingPathComponent("metadata.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: metadataURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testWallpaperStoreDeletesDownloadedFileAndMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-wallpaper-delete-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WallpaperStore(directoryURL: directory)
        let sourceURL = directory.appendingPathComponent("source.png")
        try makeTestPNG().write(to: sourceURL)
        let item = WallpaperItem(
            id: "wallhaven:delete-test",
            source: .wallhaven,
            sourceID: "delete-test",
            title: "Delete test",
            previewURL: sourceURL,
            originalURL: sourceURL,
            sourcePageURL: nil,
            authorName: nil,
            authorURL: nil,
            width: 4,
            height: 2,
            fileExtension: "png",
            licenseName: nil,
            licenseURL: nil,
            isFavorite: false,
            localFileName: nil
        )

        let savedItem = try store.save(downloadedFileURL: sourceURL, for: item)
        let storedURL = try XCTUnwrap(store.localURL(for: savedItem))
        try store.delete(savedItem)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertNil(store.localURL(for: savedItem))
        XCTAssertTrue(store.load().isEmpty)
    }

    @MainActor
    func testDesktopWallpaperServiceRejectsLockScreenTargetsBeforeTouchingScreens() {
        let service = DesktopWallpaperService(
            screensProvider: { [] }
        )

        XCTAssertThrowsError(
            try service.apply(
                imageURL: URL(fileURLWithPath: "/tmp/wallpaper.png"),
                target: .both
            )
        ) { error in
            XCTAssertEqual(error as? DesktopWallpaperServiceError, .lockScreenUnavailable)
        }
    }

    @MainActor
    func testDesktopWallpaperServiceUsesThePublicDesktopImageAPIForEachScreen() throws {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-public-wallpaper-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: imageURL) }
        try makeTestPNG().write(to: imageURL)

        var calls: [(URL, NSScreen, [NSWorkspace.DesktopImageOptionKey: Any])] = []
        let service = DesktopWallpaperService(
            screensProvider: { screens },
            setImage: { url, screen, options in
                calls.append((url, screen, options))
            }
        )

        try service.apply(imageURL: imageURL, target: .desktop)

        XCTAssertEqual(calls.count, screens.count)
        XCTAssertTrue(calls.allSatisfy { $0.0 == imageURL })
        XCTAssertTrue(
            calls.allSatisfy {
                ($0.2[.imageScaling] as? NSNumber)?.intValue ?? -1
                    == NSImageScaling.scaleProportionallyUpOrDown.rawValue
            }
        )
        XCTAssertTrue(calls.allSatisfy { ($0.2[.allowClipping] as? NSNumber)?.boolValue == true })
    }

    @MainActor
    func testWallpaperSystemServiceSynchronizesDesktopIdleAndLoginRecords() throws {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-wallpaper-system-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let indexURL = rootDirectory.appendingPathComponent("Index.plist")
        let sourceURL = rootDirectory.appendingPathComponent("source.png")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try makeTestPNG().write(to: sourceURL)

        let oldConfiguration = try PropertyListSerialization.data(
            fromPropertyList: [
                "type": "imageFile",
                "url": ["relative": "file:///old-wallpaper.png"]
            ],
            format: .binary,
            options: 0
        )
        let oldDesktop = [
            "Content": [
                "Choices": [["Configuration": oldConfiguration]]
            ]
        ] as [String: Any]
        let oldIdle = [
            "Content": [
                "Choices": [["Configuration": oldConfiguration]]
            ]
        ] as [String: Any]
        let index: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Idle": oldIdle
            ],
            "SystemDefault": [
                "Desktop": oldDesktop,
                "Idle": oldIdle
            ],
            "Spaces": [
                "space-1": [
                    "Default": [
                        "Desktop": oldDesktop,
                        "Idle": oldIdle
                    ]
                ]
            ],
            "Displays": [
                "display-1": [
                    "Desktop": oldDesktop,
                    "Idle": oldIdle
                ]
            ]
        ]
        try PropertyListSerialization.data(
            fromPropertyList: index,
            format: .binary,
            options: 0
        ).write(to: indexURL)
        let staleIndexData = try Data(contentsOf: indexURL)

        var desktopCalls: [URL] = []
        var loginWindowURL: URL?
        var refreshCount = 0
        let desktopService = DesktopWallpaperService(
            screensProvider: { screens },
            setImage: { url, _, _ in
                desktopCalls.append(url)
                // NSWorkspace can rewrite the store after an earlier write.
                // The service must write the unified state after this call.
                try staleIndexData.write(to: indexURL, options: .atomic)
            }
        )
        let service = WallpaperSystemService(
            desktopWallpaperService: desktopService,
            wallpaperIndexURL: indexURL,
            stableWallpaperDirectoryURL: rootDirectory.appendingPathComponent("SystemWallpaper"),
            setLoginWindowWallpaper: { loginWindowURL = $0 },
            refreshWallpaperAgent: { refreshCount += 1 }
        )

        try service.apply(imageURL: sourceURL, target: .both)

        let stableURL = try XCTUnwrap(loginWindowURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stableURL.path))
        XCTAssertEqual(try Data(contentsOf: stableURL), try Data(contentsOf: sourceURL))
        XCTAssertEqual(desktopCalls, Array(repeating: stableURL, count: screens.count))
        XCTAssertEqual(refreshCount, 1)

        let updatedIndexValue = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: indexURL),
            options: [],
            format: nil
        )
        let updatedIndex = try XCTUnwrap(updatedIndexValue as? [String: Any])
        let allSpaces = try XCTUnwrap(updatedIndex["AllSpacesAndDisplays"] as? [String: Any])

        func configurationURL(in value: Any?) throws -> String {
            let section = try XCTUnwrap(value as? [String: Any])
            let content = try XCTUnwrap(section["Content"] as? [String: Any])
            let choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
            let firstChoice = try XCTUnwrap(choices.first)
            let configuration = try XCTUnwrap(firstChoice["Configuration"] as? Data)
            let decodedValue = try PropertyListSerialization.propertyList(
                from: configuration,
                options: [],
                format: nil
            )
            let decoded = try XCTUnwrap(decodedValue as? [String: Any])
            let url = try XCTUnwrap(decoded["url"] as? [String: Any])
            return try XCTUnwrap(url["relative"] as? String)
        }

        XCTAssertEqual(try configurationURL(in: allSpaces["Desktop"]), stableURL.absoluteString)
        XCTAssertEqual(try configurationURL(in: allSpaces["Idle"]), stableURL.absoluteString)

        let systemDefault = try XCTUnwrap(updatedIndex["SystemDefault"] as? [String: Any])
        XCTAssertEqual(try configurationURL(in: systemDefault["Desktop"]), stableURL.absoluteString)
        XCTAssertEqual(try configurationURL(in: systemDefault["Idle"]), stableURL.absoluteString)

        let spaces = try XCTUnwrap(updatedIndex["Spaces"] as? [String: Any])
        let space = try XCTUnwrap(spaces["space-1"] as? [String: Any])
        let defaultSpace = try XCTUnwrap(space["Default"] as? [String: Any])
        XCTAssertEqual(try configurationURL(in: defaultSpace["Desktop"]), stableURL.absoluteString)
        XCTAssertEqual(try configurationURL(in: defaultSpace["Idle"]), stableURL.absoluteString)

        let displays = try XCTUnwrap(updatedIndex["Displays"] as? [String: Any])
        let display = try XCTUnwrap(displays["display-1"] as? [String: Any])
        XCTAssertEqual(try configurationURL(in: display["Desktop"]), stableURL.absoluteString)
        XCTAssertEqual(try configurationURL(in: display["Idle"]), stableURL.absoluteString)
    }

    private func makeTestPNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 2).fill()
        image.unlockFocus()

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

private struct FailingWallpaperSource: WallpaperSourceProviding {
    let source: WallpaperSource = .wallhaven

    func search(page _: Int, filters _: WallpaperSearchFilters) async throws -> WallpaperPage {
        throw WallpaperAPIError.invalidPayload
    }
}

private struct StubWallpaperSource: WallpaperSourceProviding {
    let source: WallpaperSource = .wikimedia
    let item: WallpaperItem

    func search(page _: Int, filters _: WallpaperSearchFilters) async throws -> WallpaperPage {
        WallpaperPage(items: [item], page: 1, hasNextPage: false)
    }
}
