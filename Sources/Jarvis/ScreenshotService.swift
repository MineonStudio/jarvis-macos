import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import ScreenCaptureKit

final class ScreenshotService {
    var hasScreenCaptureAccess: Bool {
        JarvisPrivacyPermissionAccess.isScreenCaptureTrusted()
    }

    func requestScreenCaptureAccess() -> Bool {
        if hasScreenCaptureAccess {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    @MainActor
    func openScreenCaptureSettings() {
        JarvisPrivacyPermissionAccess.openSettings(for: .screenCapture)
    }

    /// Freezes every connected display before Jarvis presents its own overlay.
    /// Window picking then works against these pixels, so no system content
    /// sharing picker is needed for the normal screenshot flow.
    @MainActor
    func captureFullScreens(screenFrames: [CGRect]) async throws -> [ScreenshotCapture] {
        guard !screenFrames.isEmpty else {
            throw ScreenshotError.noDisplays
        }

        return try await withThrowingTaskGroup(of: (Int, ScreenshotCapture).self) { group in
            for (index, screenFrame) in screenFrames.enumerated() {
                group.addTask {
                    try await (index, Self.capture(screenRect: screenFrame))
                }
            }

            var captures = Array(repeating: ScreenshotCapture?.none, count: screenFrames.count)
            for try await (index, capture) in group {
                captures[index] = capture
            }
            return captures.compactMap { $0 }
        }
    }

    /// Synchronous display snapshot used to freeze the screen on the same
    /// run-loop turn as F1. ScreenCaptureKit stays as the fallback because
    /// Quartz can return nil when a display is mid-reconfigure.
    @MainActor
    func captureFullScreensImmediately(screenFrames: [CGRect]) throws -> [ScreenshotCapture] {
        guard !screenFrames.isEmpty else {
            throw ScreenshotError.noDisplays
        }
        return try screenFrames.map { screenFrame in
            try Self.captureImmediately(screenRect: screenFrame)
        }
    }

    /// Captures one display-sized rectangle while retaining every visible
    /// window, including Jarvis's own main window and pinned screenshots.
    /// The direct rectangle API can omit the caller's own surfaces, so use an
    /// explicit display filter with no excluded applications.
    private static func capture(screenRect: CGRect) async throws -> ScreenshotCapture {
        guard !screenRect.isEmpty else {
            throw ScreenshotError.captureFailed("无法识别要截图的显示器")
        }

        do {
            let image = try await captureDisplayFilter(for: screenRect)
            return ScreenshotCapture(cgImage: image, screenFrame: screenRect)
        } catch let error as ScreenshotError {
            throw error
        } catch let error as NSError {
            if error.domain == SCStreamErrorDomain,
               error.code == SCStreamError.userDeclined.rawValue
            {
                throw ScreenshotError.permissionDenied
            }
            throw ScreenshotError.captureFailed(
                "ScreenCaptureKit 无法读取当前显示器：\(error.localizedDescription)"
            )
        }
    }

    private static func captureImmediately(screenRect: CGRect) throws -> ScreenshotCapture {
        guard !screenRect.isEmpty else {
            throw ScreenshotError.captureFailed("无法识别要截图的显示器")
        }
        guard let displayID = displayID(for: screenRect) else {
            throw ScreenshotError.captureFailed("无法识别要截图的显示器")
        }

        guard let cgImage = QuartzDisplaySnapshot.image(for: displayID) else {
            throw ScreenshotError.captureFailed("无法快速冻结屏幕")
        }
        return ScreenshotCapture(cgImage: cgImage, screenFrame: screenRect)
    }

    private static func captureDisplayFilter(for screenRect: CGRect) async throws -> CGImage {
        let shareableContent = try await SCShareableContent.current
        let displayID = displayID(for: screenRect)
        guard let display = shareableContent.displays.first(where: { display in
            if let displayID {
                return display.displayID == displayID
            }
            return display.frame == screenRect
        }) else {
            throw ScreenshotError.captureFailed("无法识别要截图的显示器")
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let pixelScale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((filter.contentRect.width * pixelScale).rounded()))
        configuration.height = max(1, Int((filter.contentRect.height * pixelScale).rounded()))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private static func displayID(for screenFrame: CGRect) -> CGDirectDisplayID? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }),
              let number = screen.deviceDescription[screenNumberKey] as? NSNumber
        else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func pngData(from image: CGImage, logicalSize: CGSize) -> Data? {
        let representation = NSBitmapImageRep(cgImage: image)
        representation.size = logicalSize
        return representation.representation(using: .png, properties: [:])
    }

    func crop(
        _ capture: ScreenshotCapture,
        to localRect: CGRect,
        on screenFrame: CGRect
    ) throws -> ScreenshotCapture {
        let screenBounds = CGRect(origin: .zero, size: screenFrame.size)
        let clippedRect = localRect.intersection(screenBounds)
        guard clippedRect.width > 0, clippedRect.height > 0,
              let sourceImage = NSImage(data: capture.data)
        else {
            throw ScreenshotError.invalidSelection
        }

        let sourceImageSize = sourceImage.size
        guard sourceImageSize.width > 0, sourceImageSize.height > 0 else {
            throw ScreenshotError.captureFailed("截图图像尺寸无效")
        }

        let sourceRepresentation = sourceImage.representations.first
        let pixelGeometry = ScreenshotPixelGeometry(
            canvasSize: screenFrame.size,
            pixelSize: CGSize(
                width: sourceRepresentation?.pixelsWide ?? Int(sourceImageSize.width),
                height: sourceRepresentation?.pixelsHigh ?? Int(sourceImageSize.height)
            )
        )
        // NSImage.draw(from:) expects sourceRect in the image's logical
        // coordinate space, not raw bitmap pixels. Only the destination
        // bitmap dimensions use the Retina pixel scale.
        let sourceRect = CGRect(
            x: clippedRect.minX / screenFrame.width * sourceImageSize.width,
            y: clippedRect.minY / screenFrame.height * sourceImageSize.height,
            width: clippedRect.width / screenFrame.width * sourceImageSize.width,
            height: clippedRect.height / screenFrame.height * sourceImageSize.height
        )
        let outputPixelSize = pixelGeometry.pixelSize(forCanvasRect: clippedRect)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(outputPixelSize.width),
            pixelsHigh: Int(outputPixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ScreenshotError.captureFailed("无法创建截图位图")
        }

        bitmap.size = clippedRect.size
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ScreenshotError.captureFailed("无法创建截图绘制上下文")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        sourceImage.draw(
            in: NSRect(origin: .zero, size: clippedRect.size),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.captureFailed("无法将截图编码为 PNG")
        }

        let outputFrame = CGRect(
            x: screenFrame.minX + clippedRect.minX,
            y: screenFrame.minY + clippedRect.minY,
            width: clippedRect.width,
            height: clippedRect.height
        )
        return ScreenshotCapture(data: data, screenFrame: outputFrame)
    }
}

/// The SDK has marked `CGDisplayCreateImage` unavailable in favor of
/// ScreenCaptureKit, but SCK is asynchronous and too slow for an F1 freeze.
/// The CoreGraphics symbols still exist; look them up at runtime so F1 can
/// snapshot every display on the same run-loop turn.
private enum QuartzDisplaySnapshot {
    static func image(for displayID: CGDirectDisplayID) -> CGImage? {
        displayCreateImage(displayID) ?? windowListImage(for: displayID)
    }

    private static func displayCreateImage(_ displayID: CGDirectDisplayID) -> CGImage? {
        guard let function = load(
            "CGDisplayCreateImage",
            as: (@convention(c) (CGDirectDisplayID) -> Unmanaged<CGImage>?).self
        ) else {
            return nil
        }
        return function(displayID)?.takeRetainedValue()
    }

    private static func windowListImage(for displayID: CGDirectDisplayID) -> CGImage? {
        typealias CreateImage = @convention(c) (
            CGRect,
            CGWindowListOption,
            CGWindowID,
            CGWindowImageOption
        ) -> Unmanaged<CGImage>?
        guard let function = load("CGWindowListCreateImage", as: CreateImage.self) else {
            return nil
        }
        return function(
            CGDisplayBounds(displayID),
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        )?.takeRetainedValue()
    }

    private static func load<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_NOW
        ), let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

struct ScreenshotCapture: Sendable {
    let screenFrame: CGRect
    let cgImage: CGImage?
    private let pngCache: PNGCache

    var data: Data {
        pngCache.getOrEncode {
            guard let cgImage else { return nil }
            return ScreenshotService.pngData(from: cgImage, logicalSize: screenFrame.size)
        }
    }

    var hasImage: Bool {
        cgImage != nil || pngCache.hasData
    }

    init(data: Data, screenFrame: CGRect, cgImage: CGImage? = nil) {
        self.screenFrame = screenFrame
        self.cgImage = cgImage ?? Self.makeCGImage(from: data)
        pngCache = PNGCache(data)
    }

    init(cgImage: CGImage, screenFrame: CGRect) {
        self.cgImage = cgImage
        self.screenFrame = screenFrame
        pngCache = PNGCache(nil)
    }

    private static func makeCGImage(from data: Data) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// Encodes the freeze-frame PNG on first use so F1 can show the overlay
/// before a 5K/6K encode finishes.
private final class PNGCache: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    init(_ value: Data?) {
        stored = value
    }

    var hasData: Bool {
        lock.lock()
        defer { lock.unlock() }
        if let stored, !stored.isEmpty {
            return true
        }
        return false
    }

    func getOrEncode(_ encode: () -> Data?) -> Data {
        lock.lock()
        if let stored, !stored.isEmpty {
            lock.unlock()
            return stored
        }
        lock.unlock()
        let encoded = encode() ?? Data()
        lock.lock()
        if stored == nil || stored?.isEmpty == true {
            stored = encoded
        }
        let result = stored ?? encoded
        lock.unlock()
        return result
    }
}

enum ScreenshotError: LocalizedError {
    case cancelled
    case invalidSelection
    case permissionDenied
    case noDisplays
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "截图已取消"
        case .invalidSelection: "截图区域太小，请重新框选"
        case .permissionDenied: "macOS 屏幕录制权限未开启，请在系统设置中允许贾维斯读取屏幕"
        case .noDisplays: "没有可用的显示器"
        case let .captureFailed(reason): "截图失败：\(reason)"
        }
    }
}
