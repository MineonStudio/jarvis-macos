import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class ScreenshotService {
    func requestScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    /// Freezes every connected display before Jarvis presents its own overlay.
    /// Window picking then works against these pixels, so no system content
    /// sharing picker is needed for the normal screenshot flow.
    func captureFullScreens(screenFrames: [CGRect]) async throws -> [ScreenshotCapture] {
        var captures: [ScreenshotCapture] = []
        captures.reserveCapacity(screenFrames.count)

        for screenFrame in screenFrames {
            try await captures.append(capture(screenRect: screenFrame))
        }

        return captures
    }

    /// Captures one display-sized rectangle with macOS 26's direct
    /// ScreenCaptureKit API, preserving the overlay's coordinate space.
    func capture(screenRect: CGRect) async throws -> ScreenshotCapture {
        guard !screenRect.isEmpty else {
            throw ScreenshotError.captureFailed("无法识别要截图的显示器")
        }

        do {
            let image = try await SCScreenshotManager.captureImage(in: screenRect)
            guard let data = Self.pngData(from: image, logicalSize: screenRect.size) else {
                throw ScreenshotError.captureFailed("无法将屏幕图像编码为 PNG")
            }
            return ScreenshotCapture(data: data, screenFrame: screenRect)
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

    private static func pngData(from image: CGImage, logicalSize: CGSize) -> Data? {
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
        case .cancelled: "截图已取消"
        case .invalidSelection: "截图区域太小，请重新框选"
        case .permissionDenied: "macOS 屏幕录制权限未开启，请在系统设置中允许贾维斯读取屏幕"
        case let .captureFailed(reason): "截图失败：\(reason)"
        }
    }
}
