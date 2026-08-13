import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class ScreenshotService {
    @MainActor
    private var pickerObserver: ScreenshotPickerObserver?

    /// Presents Apple's system content picker and limits the choice to one
    /// display. Jarvis keeps its own region-selection/editor UI after this
    /// step, so the user can still drag-select and annotate a sub-region.
    @MainActor
    func selectDisplay() async throws -> SCContentFilter {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleDisplay
        configuration.allowsChangingSelectedContent = false
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            configuration.excludedBundleIDs = [bundleIdentifier]
        }

        let observer = ScreenshotPickerObserver()
        pickerObserver = observer
        picker.defaultConfiguration = configuration
        picker.add(observer)
        picker.isActive = true

        defer {
            picker.isActive = false
            picker.remove(observer)
            if pickerObserver === observer {
                pickerObserver = nil
            }
        }

        picker.present(using: .display)
        return try await observer.waitForSelection()
    }

    func capture(displayFilter filter: SCContentFilter) async throws -> ScreenshotCapture {
        guard filter.style == .display else {
            throw ScreenshotError.captureFailed("系统选择器返回了非显示器来源")
        }

        let screenFrame = try screenFrame(for: filter.contentRect)
        let pixelScale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((filter.contentRect.width * pixelScale).rounded()))
        configuration.height = max(1, Int((filter.contentRect.height * pixelScale).rounded()))
        configuration.showsCursor = false
        configuration.capturesAudio = false

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            guard let data = Self.pngData(from: image, logicalSize: screenFrame.size) else {
                throw ScreenshotError.captureFailed("无法将屏幕图像编码为 PNG")
            }
            return ScreenshotCapture(data: data, screenFrame: screenFrame)
        } catch let error as ScreenshotError {
            throw error
        } catch let error as NSError {
            if error.domain == SCStreamErrorDomain,
               error.code == SCStreamError.userDeclined.rawValue {
                throw ScreenshotError.permissionDenied
            }
            throw ScreenshotError.captureFailed(
                "ScreenCaptureKit 无法读取所选显示器：\(error.localizedDescription)"
            )
        }
    }

    private func screenFrame(for contentRect: CGRect) throws -> CGRect {
        guard let screen = NSScreen.screens.first(where: { screen in
            abs(screen.frame.minX - contentRect.minX) < 1
                && abs(screen.frame.minY - contentRect.minY) < 1
                && abs(screen.frame.width - contentRect.width) < 1
                && abs(screen.frame.height - contentRect.height) < 1
        }) else {
            throw ScreenshotError.captureFailed("无法定位系统选择的显示器")
        }
        return screen.frame
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

private final class ScreenshotPickerObserver: NSObject, @unchecked Sendable, SCContentSharingPickerObserver {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SCContentFilter, Error>?
    private var pendingResult: Result<SCContentFilter, Error>?
    private var didFinish = false

    func waitForSelection() async throws -> SCContentFilter {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let pendingResult {
                self.pendingResult = nil
                lock.unlock()
                continuation.resume(with: pendingResult)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        finish(.failure(ScreenshotError.cancelled))
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        finish(.success(filter))
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        finish(.failure(ScreenshotError.captureFailed(
            "系统内容选择器启动失败：\(error.localizedDescription)"
        )))
    }

    private func finish(_ result: Result<SCContentFilter, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            pendingResult = result
            lock.unlock()
        }
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
