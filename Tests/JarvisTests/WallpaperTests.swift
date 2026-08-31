import AppKit
@testable import Jarvis
import XCTest

final class WallpaperTests: XCTestCase {
    func testWallpaperSourceIsWallhavenAndKeepsLegacyLocalRecordsDecodable() {
        XCTAssertEqual(WallpaperSource.wallhaven.title, "Wallhaven")
        XCTAssertEqual(WallpaperSource.local.title, "本地")
    }

    func testWallpaperFiltersExposeWallhavenResolutionAndCategoryOptions() {
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
        XCTAssertEqual(WallpaperCategory.all.apiValue, "111")
        XCTAssertEqual(WallpaperCategory.general.apiValue, "100")
        XCTAssertEqual(WallpaperCategory.anime.apiValue, "010")
        XCTAssertEqual(WallpaperCategory.people.apiValue, "001")
        XCTAssertEqual(WallpaperCategory.generalAnime.apiValue, "110")
        XCTAssertEqual(WallpaperCategory.generalPeople.apiValue, "101")
        XCTAssertEqual(WallpaperCategory.animePeople.apiValue, "011")
    }

    func testWallpaperRatioAndTagFiltersExposeWallhavenQueries() {
        XCTAssertEqual(WallpaperRatio.landscape.apiValue, "16x9,16x10,21x9,32x9")
        XCTAssertEqual(WallpaperRatio.portrait.apiValue, "9x16,10x16")
        XCTAssertEqual(WallpaperRatio.square.apiValue, "1x1")
        XCTAssertNil(WallpaperRatio.any.apiValue)
        XCTAssertTrue(WallpaperTags.popular.contains { $0.query == "landscape" })
        XCTAssertTrue(WallpaperTags.popular.contains { $0.query == "space" })
        XCTAssertEqual(
            WallpaperSorting.allCases.map(\.apiValue),
            ["toplist", "date_added", "relevance", "views", "favorites"]
        )
    }

    @MainActor
    func testWallpaperDefaultsUseLatestSortingAndExpandedInitialBatch() {
        let filters = WallpaperSearchFilters()

        XCTAssertEqual(filters.sorting, .dateAdded)
        XCTAssertEqual(filters.sorting.title, "最新")
        XCTAssertEqual(WallpaperViewModel.initialDisplayCount, 36)
    }

    func testWallpaperLibraryModesExposeOnlineDownloadedAndFavorites() {
        XCTAssertEqual(
            WallpaperLibraryMode.allCases.map(\.title),
            ["在线图库", "已下载", "我的收藏"]
        )
    }

    func testWallpaperSkillUsesDesktopWallpaperName() {
        XCTAssertEqual(SkillID.wallpaper.title, "桌面壁纸技能")
        XCTAssertEqual(SkillID.wallpaper.navigationTitle, "桌面壁纸")
    }

    func testWallpaperSearchFiltersDefaultToUnrestrictedValues() {
        let filters = WallpaperSearchFilters()

        XCTAssertEqual(filters.resolution, .any)
        XCTAssertEqual(filters.category, .all)
        XCTAssertEqual(filters.ratio, .any)
        XCTAssertEqual(filters.resolution.title, "不限分辨率")
        XCTAssertEqual(filters.category.title, "全部分类")
        XCTAssertEqual(filters.ratio.title, "不限比例")
    }

    func testWallhavenSearchURLContainsAllSelectedFilters() throws {
        let filters = WallpaperSearchFilters(
            resolution: .uwqhd,
            category: .generalAnime,
            ratio: .twentyOneByNine,
            sorting: .dateAdded,
            tag: "cyberpunk"
        )
        let url = try WallhavenWallpaperSource.searchURL(page: 3, filters: filters)
        let queryItems = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

        XCTAssertEqual(query["categories"], "110")
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
                    "large": "https://th.wallhaven.cc/lg/ab/abc123.jpg"
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
        var setImageCallCount = 0
        let service = DesktopWallpaperService(
            screensProvider: { [] },
            setImage: { _, _, _ in setImageCallCount += 1 }
        )

        XCTAssertThrowsError(
            try service.apply(
                imageURL: URL(fileURLWithPath: "/tmp/wallpaper.png"),
                target: .both
            )
        ) { error in
            XCTAssertEqual(error as? DesktopWallpaperServiceError, .lockScreenUnavailable)
        }
        XCTAssertEqual(setImageCallCount, 0)
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
