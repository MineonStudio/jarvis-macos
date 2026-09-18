import AppKit
@testable import Jarvis
import XCTest

/// 贴图（中键贴到屏幕上那张图）的右键菜单：复制 / 编辑 / 隐藏·显示阴影 / 销毁。
///
/// 菜单项是 `NSMenuItem` 的手工接线，接错（复制接到销毁上、编辑永远置灰）不会有
/// 任何编译信号，所以这里把标题、动作和开关都钉住；阴影那一项还要真的量一遍画出来
/// 的光晕，免得只翻了个标志位、画面上没有任何变化。
@MainActor
final class ScreenshotPinnedMenuTests: XCTestCase {
    private let imageSize = CGSize(width: 160, height: 120)

    private func makeEditor() -> ScreenshotEditorModel {
        let canvas = CGSize(width: 160, height: 120)
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        image.unlockFocus()
        return ScreenshotEditorModel(
            image: image,
            data: Data(),
            outputData: Data(),
            canvasSize: canvas,
            outputRect: CGRect(origin: .zero, size: canvas)
        )
    }

    private func makeContainer(canEdit: Bool = true) -> PinnedScreenshotContainerView {
        let view = PinnedScreenshotContainerView(
            frame: NSRect(x: 0, y: 0, width: 240, height: 200),
            imageSize: imageSize,
            contentInset: 40,
            editor: makeEditor(),
            onActivate: nil
        )
        view.canEdit = { canEdit }
        return view
    }

    private func menu(of view: NSView) throws -> NSMenu {
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        return try XCTUnwrap(view.menu(for: event), "右键应当弹得出菜单")
    }

    private func actionableItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.filter { !$0.isSeparatorItem }
    }

    func testTheMenuOffersTheFourPinActionsInOrder() throws {
        let view = makeContainer()
        let menu = try menu(of: view)

        XCTAssertEqual(
            actionableItems(menu).map(\.title),
            ["复制图片", "编辑", "隐藏阴影", "销毁"]
        )
        XCTAssertEqual(
            menu.items.map(\.isSeparatorItem),
            [false, false, false, true, false],
            "「销毁」是破坏性动作，要和上面几项隔开"
        )
    }

    /// 每一项都得接上自己的动作，而且各不相同——手抄一行最容易接错。
    func testEveryItemIsWiredToItsOwnAction() throws {
        let view = makeContainer()
        let menu = try menu(of: view)

        for item in actionableItems(menu) {
            XCTAssertNotNil(item.action, "「\(item.title)」没有接动作")
            XCTAssertNotNil(item.target, "「\(item.title)」没有目标，点了会落空")
        }
        XCTAssertEqual(
            Set(actionableItems(menu).compactMap { $0.action.map(NSStringFromSelector) }),
            [
                "copyImageToPasteboard",
                "editPin",
                "toggleShadow",
                "destroyPin"
            ]
        )
    }

    /// 另一场编辑进行中时「编辑」置灰——控制器给出的判断要能真的落到菜单上。
    func testEditIsDisabledWhileAnotherEditIsOpen() throws {
        let busy = makeContainer(canEdit: false)
        let editItem = try XCTUnwrap(
            actionableItems(try menu(of: busy)).first { $0.title == "编辑" }
        )
        XCTAssertFalse(editItem.isEnabled)

        let free = makeContainer(canEdit: true)
        let enabledItem = try XCTUnwrap(
            actionableItems(try menu(of: free)).first { $0.title == "编辑" }
        )
        XCTAssertTrue(enabledItem.isEnabled)
    }

    /// 「编辑」和「销毁」要真的走到控制器接上去的那条路。
    func testEditAndDestroyCallBackIntoTheController() throws {
        let view = makeContainer()
        var editCount = 0
        var destroyCount = 0
        view.onEdit = { editCount += 1 }
        view.onDestroy = { destroyCount += 1 }

        let menu = try menu(of: view)
        let editItem = try XCTUnwrap(actionableItems(menu).first { $0.title == "编辑" })
        let destroyItem = try XCTUnwrap(actionableItems(menu).first { $0.title == "销毁" })
        _ = view.perform(try XCTUnwrap(editItem.action), with: editItem)
        _ = view.perform(try XCTUnwrap(destroyItem.action), with: destroyItem)

        XCTAssertEqual(editCount, 1)
        XCTAssertEqual(destroyCount, 1)
    }

    /// 标题报的是点下去会做什么，所以它跟着当前状态翻。
    func testTheShadowTitleReportsWhatTheClickWillDo() throws {
        let view = makeContainer()
        XCTAssertTrue(view.showsShadow)
        XCTAssertEqual(
            actionableItems(try menu(of: view)).first { $0.title.contains("阴影") }?.title,
            "隐藏阴影"
        )

        view.showsShadow = false
        XCTAssertEqual(
            actionableItems(try menu(of: view)).first { $0.title.contains("阴影") }?.title,
            "显示阴影"
        )
    }
}

extension ScreenshotPinnedMenuTests {
    /// 图片**外面**哪里采样。
    private enum SampleRegion {
        /// 离图片边缘 8pt 开外：光晕铺开的地方。
        case halo
        /// 紧贴图片边缘的外侧 4pt：选中描边待的地方。
        case edge
    }

    /// 某个区域里最不透明的一个像素。
    ///
    /// 光晕和描边都画在图片外面（透明内缩区里），图片本身是子视图压在最上面的，
    /// 所以只能在外面量。
    private func strongestAlpha(of view: NSView, in region: SampleRegion) throws -> CGFloat {
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFront(nil)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        defer { window.orderOut(nil) }

        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        let scaleX = CGFloat(rep.pixelsWide) / view.bounds.width
        let scaleY = CGFloat(rep.pixelsHigh) / view.bounds.height
        let imageRect = CGRect(origin: CGPoint(x: 40, y: 40), size: imageSize)
        var strongest: CGFloat = 0
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                let point = CGPoint(x: CGFloat(x) / scaleX, y: CGFloat(y) / scaleY)
                let outsideBy = max(
                    max(imageRect.minX - point.x, point.x - imageRect.maxX),
                    max(imageRect.minY - point.y, point.y - imageRect.maxY)
                )
                guard outsideBy > 0 else { continue }
                switch region {
                case .halo where outsideBy < 8: continue
                case .edge where outsideBy > 4: continue
                default: break
                }
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                strongest = max(strongest, color.alphaComponent)
            }
        }
        return strongest
    }

    /// 关掉阴影之后画面上要真的没有那圈光晕。
    func testHidingTheShadowRemovesTheHaloFromTheDrawing() throws {
        let view = makeContainer()
        view.showsShadow = true
        let withHalo = try strongestAlpha(of: view, in: .halo)
        view.showsShadow = false
        let withoutHalo = try strongestAlpha(of: view, in: .halo)

        XCTAssertGreaterThan(withHalo, 0.02, "开着阴影时图片外面应当有光晕")
        XCTAssertLessThan(withoutHalo, withHalo / 4, "关掉之后那一圈应当基本透明")
    }

    /// 选中描边不能跟着阴影一起消失：关掉光晕之后，它是唯一说明这张贴图被选中的
    /// 东西。它还得画在图片外面——画在图片范围内会被图片整个盖住（原来那条就是
    /// 这么看不见的）。
    func testSelectionStaysVisibleWithoutTheShadow() throws {
        let view = makeContainer()
        view.showsShadow = false

        view.isSelected = false
        let unselected = try strongestAlpha(of: view, in: .edge)
        view.isSelected = true
        let selected = try strongestAlpha(of: view, in: .edge)

        XCTAssertGreaterThan(selected, 0.2, "选中时图片边缘外面应当有描边")
        XCTAssertLessThan(unselected, 0.05, "没选中时图片边缘外面不该有东西")
    }
}

extension ScreenshotPinnedMenuTests {
    /// 编辑会话里的动作 → 贴图该怎么收场。
    func testTheEditOutcomeTable() {
        let saved = Data([1, 2, 3])
        let newer = Data([4, 5, 6])

        // 「完成」当场写回。
        XCTAssertEqual(
            ScreenshotCaptureController.pinnedEditOutcome(for: .confirm(newer), committedData: saved),
            .apply(newer)
        )
        // 「保存」在这一刻什么都不做：它是在保存面板弹出来**之前**发出的，用户在
        // 面板上点取消也照样发过一次。真存下盘了由 AppModel 回头说（notePinnedEditSaved）。
        XCTAssertEqual(
            ScreenshotCaptureController.pinnedEditOutcome(for: .save(newer), committedData: nil),
            .ignore
        )
        // 中键贴图的结果已经在 pinScreenshot 里换过了，这里不能再换一遍。
        XCTAssertEqual(
            ScreenshotCaptureController.pinnedEditOutcome(for: .pin(newer), committedData: nil),
            .ignore
        )
        // Esc：什么都没存过就原样放回去。
        XCTAssertEqual(
            ScreenshotCaptureController.pinnedEditOutcome(for: .cancel, committedData: nil),
            .restore
        )
        // Esc：存过盘就用存过的那份——存过盘的一次编辑不该因为按了 Esc 就看不见了。
        XCTAssertEqual(
            ScreenshotCaptureController.pinnedEditOutcome(for: .cancel, committedData: saved),
            .apply(saved)
        )
        // 编辑面里的其它动作（工具、撤销）与贴图无关。
        XCTAssertEqual(
            ScreenshotCaptureController.pinnedEditOutcome(for: .undo, committedData: nil),
            .ignore
        )
    }

    /// 「就地更新」靠的是这段换算：贴图的窗口比图片大一圈（留光晕的地方），
    /// `imageFrame` 把那一圈减回去。编辑完按这个矩形重建，图就还在原地。
    func testAPinReportsTheImageFrameOfItsWindow() throws {
        let frame = CGRect(x: 300, y: 240, width: 160, height: 120)
        let item = PinnedScreenshotItem(
            data: try XCTUnwrap(pngData(size: imageSize)),
            image: NSImage(size: imageSize),
            frame: frame
        )

        XCTAssertEqual(item.imageFrame, frame, "重建贴图用的就是它，位置不能漂")
    }

    private func pngData(size: CGSize) throws -> Data? {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let rep = try XCTUnwrap(
            NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))
        )
        return rep.representation(using: .png, properties: [:])
    }
}
