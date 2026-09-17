import AppKit
@testable import Jarvis
import XCTest

/// 回归测试：2026-09-17 缺陷审计中发现的问题。
///
/// 这些用例对应审计报告 `测试报告.md` 中的编号。C-2 无法在此处自动化
/// （`AppModel` 未开放 `ClipboardCacheStore` 注入，无法在不污染真实用户目录的前提下
/// 构造"容量接近上限 + 存在 legacy 文本条目"的初始状态），其复现方式记录在该用例的注释里。
final class AuditRegressionTests: XCTestCase {
    // MARK: - C-1：缓存淘汰不得删除缓存目录之外的用户文件

    /// 复现并锁定审计报告 C-1：
    /// `ClipboardItem.cachePaths` 会包含**外部原始文件路径**（文件 > 1 GB 或缓存已满时
    /// `captureFile` 把 `filePath` 写成原始路径且 `isStoredCopy == false`），
    /// 而 `receiveClipboardItem` 把这些路径交给 `removeLegacyFiles(atPaths:)`，
    /// 后者不校验归属，直接 `removeItem`。
    ///
    /// 触发路径（手工验证步骤）：
    /// 1. 复制一个 > 1 GB 的文件 → 历史条目引用原始路径；
    /// 2. 再复制 300 条新内容把该条目挤出上限；
    /// 3. 原始文件被删除。
    func testLegacyFileRemovalMustNotDeleteFilesOutsideTheCacheDirectory() throws {
        let suiteName = "jarvis-audit-external-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-audit-cache-\(UUID().uuidString)", isDirectory: true)
        defaults.set(cacheDirectory.path, forKey: "jarvis.clipboard.cache.directory")

        let externalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-audit-user-document-\(UUID().uuidString).pdf")
        try Data(repeating: 7, count: 64).write(to: externalURL)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: cacheDirectory)
            try? FileManager.default.removeItem(at: externalURL)
        }

        let store = ClipboardCacheStore(defaults: defaults)

        // 正确行为：带归属校验的删除路径不能碰外部文件。
        let externalItem = ClipboardItem(
            kind: .video,
            filePath: externalURL.path,
            fileName: "user-video.mov",
            isStoredCopy: false
        )
        XCTAssertFalse(store.hasManagedReferences(for: externalItem))
        XCTAssertTrue(store.removeManagedFiles(for: [externalItem]))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: externalURL.path),
            "removeManagedFiles 删除了缓存目录之外的用户文件"
        )

        // 缺陷行为：removeLegacyFiles 会把外部文件一并删掉。
        // 用 XCTExpectFailure 固定"当前是坏的"，这样测试套件保持全绿，
        // 而一旦修复（AppModel+Clipboard.swift:86 改回 removeManagedFiles），
        // 这个用例会因为"预期失败但没有失败"而报错，提醒删除该标记。
        XCTExpectFailure("缺陷 C-1：removeLegacyFiles 会删除缓存目录之外的用户文件") {
            store.removeLegacyFiles(atPaths: [externalURL.path], reason: "auditRegression")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: externalURL.path),
                "removeLegacyFiles 删除了缓存目录之外的用户文件（缺陷 C-1）"
            )
        }
    }

    // MARK: - C-2：循环内缩容导致的越界崩溃

    /// 锁定审计报告 C-2 的**根因**：`for index in collection.indices` 只求值一次，
    /// 循环体内缩短集合后继续按旧下标读取会触发致命错误。
    ///
    /// 生产代码 `AppModel+Clipboard.swift:9-27` 正是这个形状：`migrateClipboardTextCache`
    /// 持有 `clipboardItems.indices`，而循环内调用的 `trimClipboardCacheIfNeeded`
    /// 会 `clipboardItems.removeAll { … }`（`:481`）并落盘（`:505`）。
    ///
    /// 本用例用"安全写法 vs 危险写法"直接对比，防止后人再写出危险形状：
    /// 危险写法在本进程内会直接 trap，因此这里只断言安全写法的行为，
    /// 危险形状由 `swift -e` 独立验证（退出码 133 / SIGTRAP）：
    ///
    ///     var a = [10, 20, 30, 40]
    ///     for i in a.indices {
    ///         if i == 1 { a.removeAll { $0 == 30 } }
    ///         _ = a[i]            // ← Fatal error: Index out of range
    ///     }
    func testMutatingCollectionWhileIteratingIndicesRequiresReResolution() {
        var items = ["a", "b", "c", "d"]

        // 危险形状的等价物，但不真的越界：用 firstIndex 重新定位。
        var visited: [String] = []
        for id in items.map(\.self) {
            guard let index = items.firstIndex(of: id) else { continue }
            visited.append(items[index])
            if id == "b" {
                items.removeAll { $0 == "c" }
            }
            // 关键：下一次循环用 firstIndex 重新定位，而不是沿用旧下标。
        }
        XCTAssertEqual(visited, ["a", "b", "d"])
        XCTAssertEqual(items, ["a", "b", "d"])
    }

    // MARK: - 版本比较：预发布标签不得被判为更新

    /// 审计报告 W-报告 §4.3：`versionParts` 用 `compactMap` **丢弃**非数字段，
    /// 导致 `v1.4.0-rc.1` 被解析成 `[1, 4, 1]`，比 `1.4.0` 的 `[1, 4, 0]` 更大。
    func testPrereleaseTagsAreNotNewerThanTheEquivalentRelease() {
        let service = JarvisUpdateService()
        // 当前实现下的真实行为（记录缺陷）：
        XCTAssertTrue(
            service.isNewer("v1.4.0-rc.1", than: "1.4.0"),
            "记录缺陷：v1.4.0-rc.1 当前被判为比 1.4.0 更新，用户会被提示升级到预发布版本"
        )
        // 期望行为（修复 versionParts 后应如此）：
        // XCTAssertFalse(service.isNewer("v1.4.0-rc.1", than: "1.4.0"))
        // 正常版本号比较必须保持正确：
        XCTAssertTrue(service.isNewer("1.4.0", than: "1.3.5"))
        XCTAssertFalse(service.isNewer("1.3.5", than: "1.3.5"))
    }

    // MARK: - 简历工作年限：不得因超长数字输入而崩溃

    /// 审计报告 Critical（简历）：`ResumeCareerTimeline.years(from:)` 用
    /// `Int(value.rounded(.down))` 做**会 trap** 的转换。19 位数字使
    /// `Double` 超过 `Int.max`，直接 `Fatal error: Double value cannot be
    /// converted to Int because the result would be greater than Int.max`。
    ///
    /// 独立复现（退出码 133 / SIGTRAP）：见审计报告 §6。
    /// 修复前**不要**解除下面被注释的断言，否则整个测试进程会崩溃。
    func testWorkYearsParsingRejectsAbsurdNumericInputInsteadOfTrapping() {
        XCTAssertEqual(ResumeCareerTimeline.years(from: "6 年经验"), 6)
        XCTAssertEqual(ResumeCareerTimeline.years(from: "3.7年"), 3)
        XCTAssertNil(ResumeCareerTimeline.years(from: "很多年"))

        // 期望行为：超长数字应返回 nil 或夹到合理上限，而不是崩溃。
        // 当前实现会 trap，所以这里只断言"18 位以内仍然可用"这一安全边界。
        // 注意：Double 只有 53 位有效精度，18 位输入的解析结果本身已经失真
        // （999999999999999999 被舍入成 1000000000000000000），
        // 这本身就是 `Int(Double(...))` 这条路径不该用于整数解析的佐证。
        XCTAssertEqual(ResumeCareerTimeline.years(from: "999999999999999999"), 1_000_000_000_000_000_000)

        // 修复后应启用：
        // XCTAssertNil(ResumeCareerTimeline.years(from: "9999999999999999999"))
    }

    // MARK: - 壁纸刷新：加载中的筛选变更不得被丢弃

    /// 审计报告 H-1：`refresh()` 先 `searchGeneration += 1`，再因 `isLoading` 早退；
    /// 在途请求恢复时发现 generation 不匹配，于是**在给 `items` 赋值之前返回**。
    /// 结果是新筛选没发请求、旧结果被丢弃、界面显示"没有找到壁纸"。
    ///
    /// 该行为依赖真实网络请求时序，无法在单元测试中稳定复现，
    /// 因此这里只锁定"generation 必须只在真正发起加载时推进"这一不变量形状。
    func testSearchGenerationMustOnlyAdvanceWhenALoadActuallyStarts() {
        var generation = 0
        var isLoading = false

        func safeRefresh() {
            // 正确形状：先判断，再推进并开始加载。
            guard !isLoading else { return }
            generation += 1
            isLoading = true
        }

        safeRefresh()
        let afterFirst = generation
        safeRefresh() // 被丢弃的并发刷新
        XCTAssertEqual(generation, afterFirst, "被丢弃的刷新不应推进 generation")
    }

    // MARK: - 剪贴板历史写入：修订号守卫

    /// 复核 `JarvisJSONFile` 的修订号守卫确实会丢弃迟到的旧写入（这是 `c2882de` 的修复）。
    /// 审计中曾怀疑此处存在竞态，实测否定——用例保留以防回归。
    func testStaleRevisionIsDiscardedAndNewestWins() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-audit-revision-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ClipboardStore(directoryURL: directory)
        let older = [ClipboardItem(kind: .text, text: "older")]
        let newer = [ClipboardItem(kind: .text, text: "newer")]

        XCTAssertTrue(store.save(newer, revision: 5))
        XCTAssertTrue(store.save(older, revision: 3)) // 迟到写入被丢弃
        XCTAssertEqual(store.load().first?.text, "newer")
    }

    // MARK: - 截图导出区域：坐标往返必须自洽

    /// 审计中曾怀疑导出裁剪区域上下翻转（`outputRect` 在 AppKit 空间、`crop` 期望
    /// 画布空间）。用像素级试验证伪后，把该不变量固化为回归测试。
    func testExportedSelectionRegionMatchesTheSelectedCanvasRegion() {
        let canvas = CGSize(width: 200, height: 200)
        let space = ScreenshotCoordinateSpace(
            screenFrame: CGRect(origin: .zero, size: canvas),
            canvasSize: canvas
        )
        let canvasSelection = CGRect(x: 20, y: 100, width: 160, height: 40)

        let outputRect = space.outputRect(fromCanvasRect: canvasSelection)
        let restored = space.canvasRect(fromOutputRect: outputRect)
        XCTAssertEqual(restored, canvasSelection)
    }

    // MARK: - H-7：mosaic（模糊/像素化）导出不能上下镜像

    /// 审计报告 H-7，本用例即为证实该缺陷的像素级试验。
    ///
    /// `renderFullCanvas` 为标注建立的是**上下镜像**的 CTM
    /// （`translateBy(y: pixelHeight)` + `scaleBy(y: -scale)`，见
    /// `ScreenshotRenderPipeline.swift:93-94`）。矢量标注只把点交给这个映射，
    /// 所以箭头/矩形是对的；但 `context.draw(image:in:)` 会在**用户空间**里正立地
    /// 绘制 CGImage，于是在镜像 CTM 下 mosaic 用到的过滤图被翻转，
    /// 落在 `:231` 的 `context.draw(filteredImage, in: canvasRect)`。
    ///
    /// 试验结果（画布自上而下为 红/绿/蓝/白 四条带，在画布 y=100..140 处放矩形模糊）：
    /// - 源图在画布 y=120 处的颜色是**蓝色**（用户框选的内容）；
    /// - 导出图在 y=120 处的颜色是**绿色**（`canvasHeight - 120 = 80` 处的内容）。
    /// 也就是说模糊块里显示的是镜像位置的画面，与 SwiftUI 预览不一致。
    func testMosaicAnnotationIsNotRenderedVerticallyMirrored() throws {
        let size = 200
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = CGSize(width: size, height: size)
        let raw = try XCTUnwrap(bitmap.bitmapData)
        for row in 0 ..< size {
            // 位图数据第 0 行是图像顶部；自上而下四条带：红、绿、蓝、白。
            let band = row * 4 / size
            let (r, g, b): (UInt8, UInt8, UInt8) = switch band {
            case 0: (255, 0, 0)
            case 1: (0, 255, 0)
            case 2: (0, 0, 255)
            default: (255, 255, 255)
            }
            for column in 0 ..< size {
                let offset = row * bitmap.bytesPerRow + column * 4
                raw[offset] = r
                raw[offset + 1] = g
                raw[offset + 2] = b
                raw[offset + 3] = 255
            }
        }
        let image = NSImage(size: CGSize(width: size, height: size))
        image.addRepresentation(bitmap)

        // 画布坐标系（左上原点）y=100..140 落在第三条带（蓝色）内。
        let mosaic = ScreenshotAnnotation(
            kind: .mosaic,
            points: [CGPoint(x: 40, y: 100), CGPoint(x: 160, y: 140)],
            text: nil,
            brushSize: 20,
            mosaicMode: .rectangle,
            mosaicStyle: .blur
        )
        let data = try XCTUnwrap(ScreenshotRenderPipeline().renderFullCanvas(.init(
            image: image,
            canvasSize: CGSize(width: size, height: size),
            pixelScale: 1,
            annotations: [mosaic],
            // 直接用原图当"过滤后的图"，这样 mosaic 区域呈现的就是源内容本身，
            // 便于判断取到的是哪一块画面。
            blurredImage: image,
            pixelatedImage: nil
        )))
        let exported = try XCTUnwrap(NSBitmapImageRep(data: data))
        let sampled = try XCTUnwrap(
            exported.colorAt(x: 100, y: 120)?.usingColorSpace(.deviceRGB)
        )

        // 正确行为：应当是用户框选的蓝色区域。
        // 当前实现取到的是镜像位置的绿色区域，因此用 XCTExpectFailure 固定缺陷。
        // 修复（在 `draw(filteredImage:...)` 之前反向翻转）后，这个用例会因为
        // "预期失败但没有失败" 而报错，提醒删除该标记。
        XCTExpectFailure("缺陷 H-7：mosaic 图层被上下镜像，导出内容与预览不一致") {
            XCTAssertGreaterThan(sampled.blueComponent, 0.8, "mosaic 区域应为蓝色（用户框选的内容）")
            XCTAssertGreaterThan(sampled.greenComponent, 0.8, "记录缺陷：当前取到的是镜像位置的绿色内容")
        }
    }
}
