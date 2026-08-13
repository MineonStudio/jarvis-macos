import AppKit
import CoreGraphics
import Foundation

final class ScreenshotService {
    func requestScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    func captureFullScreens(screenFrames: [CGRect]) async throws -> [ScreenshotCapture] {
        var captures: [ScreenshotCapture] = []
        captures.reserveCapacity(screenFrames.count)

        for screenFrame in screenFrames {
            captures.append(try await capture(screenRect: screenFrame))
        }

        return captures
    }

    func capture(screenRect: CGRect) async throws -> ScreenshotCapture {
        // CGDisplayCreateImage can return a desktop-only image when the
        // process lacks Screen Recording permission. Treat that as denied
        // instead of saving a misleading wallpaper screenshot.
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenshotError.permissionDenied
        }

        guard let displayID = displayID(for: screenRect) else {
            throw ScreenshotError.captureFailed("无法识别要截图的显示器")
        }

        // Capture the display directly through CoreGraphics. Calling the
        // /usr/sbin/screencapture helper from a detached Process made the
        // result depend on the helper's own TCC/code-signing identity and hid
        // every failure behind a misleading "permission denied" error.
        let data = try await Task.detached(priority: .userInitiated) {
            guard let image = CGDisplayCreateImage(displayID) else {
                if !CGPreflightScreenCaptureAccess() {
                    throw ScreenshotError.permissionDenied
                }
                throw ScreenshotError.captureFailed("CoreGraphics 无法读取当前显示器")
            }

            let representation = NSBitmapImageRep(cgImage: image)
            representation.size = screenRect.size
            guard let data = representation.representation(using: .png, properties: [:]),
                  !data.isEmpty else {
                throw ScreenshotError.captureFailed("无法将屏幕图像编码为 PNG")
            }
            return data
        }.value

        return ScreenshotCapture(data: data, screenFrame: screenRect)
    }

    private func displayID(for screenFrame: CGRect) -> CGDirectDisplayID? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }),
              let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    func crop(
        _ capture: ScreenshotCapture,
        to localRect: CGRect,
        on screenFrame: CGRect
    ) throws -> ScreenshotCapture {
        let screenBounds = CGRect(origin: .zero, size: screenFrame.size)
        let clippedRect = localRect.intersection(screenBounds)
        guard clippedRect.width > 0, clippedRect.height > 0,
              let sourceImage = NSImage(data: capture.data) else {
            throw ScreenshotError.invalidSelection
        }

        let sourceImageSize = sourceImage.size
        guard sourceImageSize.width > 0, sourceImageSize.height > 0 else {
            throw ScreenshotError.permissionDenied
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
            throw ScreenshotError.permissionDenied
        }

        bitmap.size = clippedRect.size
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ScreenshotError.permissionDenied
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
            throw ScreenshotError.permissionDenied
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

struct ScreenshotCapture: Sendable {
    let data: Data
    let screenFrame: CGRect
}

enum ScreenshotError: LocalizedError {
    case cancelled
    case invalidSelection
    case permissionDenied
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "截图已取消"
        case .invalidSelection: return "截图区域太小，请重新框选"
        case .permissionDenied: return "macOS 屏幕录制权限未开启，请在系统设置中允许贾维斯读取屏幕"
        case .captureFailed(let reason): return "截图失败：\(reason)"
        }
    }
}
