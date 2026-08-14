import CoreGraphics

/// The screenshot pipeline uses AppKit's bottom-left screen coordinates at
/// its boundaries and SwiftUI's top-left canvas coordinates while editing.
/// Keep that conversion in one small, testable value type.
struct ScreenshotCoordinateSpace: Equatable, Sendable {
    let screenFrame: CGRect
    let canvasSize: CGSize

    func canvasRect(fromOutputRect outputRect: CGRect) -> CGRect {
        CGRect(
            x: outputRect.minX,
            y: canvasSize.height - outputRect.maxY,
            width: outputRect.width,
            height: outputRect.height
        )
    }

    func outputRect(fromCanvasRect canvasRect: CGRect) -> CGRect {
        CGRect(
            x: canvasRect.minX,
            y: canvasSize.height - canvasRect.maxY,
            width: canvasRect.width,
            height: canvasRect.height
        )
    }

    func screenRect(fromOutputRect outputRect: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + outputRect.minX,
            y: screenFrame.minY + outputRect.minY,
            width: outputRect.width,
            height: outputRect.height
        )
    }

    func clampedCanvasRect(_ rect: CGRect, minimumSize: CGFloat = 24) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let clamped = rect.intersection(bounds)
        guard clamped.width >= minimumSize, clamped.height >= minimumSize else {
            return nil
        }
        return clamped
    }
}

/// Maps logical canvas points to the pixels in a captured image. Keeping this
/// separate prevents Retina scaling from being reimplemented in every crop or
/// renderer call site.
struct ScreenshotPixelGeometry: Equatable, Sendable {
    let canvasSize: CGSize
    let pixelSize: CGSize

    var scaleX: CGFloat {
        pixelSize.width / max(canvasSize.width, 1)
    }

    var scaleY: CGFloat {
        pixelSize.height / max(canvasSize.height, 1)
    }

    func pixelRect(fromCanvasRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }

    func pixelSize(forCanvasRect rect: CGRect) -> CGSize {
        CGSize(
            width: CGFloat(max(1, Int((rect.width * scaleX).rounded()))),
            height: CGFloat(max(1, Int((rect.height * scaleY).rounded())))
        )
    }
}
