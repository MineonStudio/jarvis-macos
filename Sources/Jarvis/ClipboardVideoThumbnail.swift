import AppKit
import AVFoundation
import Foundation

enum ClipboardVideoThumbnailGenerator {
    static func makeCGImage(
        for url: URL,
        maxPixelSize: Int = 640
    ) async -> CGImage? {
        await withCheckedContinuation { continuation in
            makeCGImageAsync(for: url, maxPixelSize: maxPixelSize) { image in
                continuation.resume(returning: image)
            }
        }
    }

    static func makeCGImageAsync(
        for url: URL,
        maxPixelSize: Int = 640,
        completion: @escaping @MainActor @Sendable (CGImage?) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            guard FileManager.default.fileExists(atPath: url.path) else {
                Task { @MainActor in completion(nil) }
                return
            }

            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let pixelSize = CGFloat(max(160, maxPixelSize))
            generator.maximumSize = CGSize(width: pixelSize, height: pixelSize)

            // Prefer a frame shortly after the start so a fade-in does not
            // leave every card black, then fall back to the first frame for
            // very short or unusual containers.
            generateFrame(
                with: AVAssetImageGeneratorBox(generator),
                at: [0.1, 0.0],
                index: 0,
                completion: completion
            )
        }
    }

    private static func generateFrame(
        with generatorBox: AVAssetImageGeneratorBox,
        at seconds: [Double],
        index: Int,
        completion: @escaping @MainActor @Sendable (CGImage?) -> Void
    ) {
        guard index < seconds.count else {
            Task { @MainActor in completion(nil) }
            return
        }

        let generator = generatorBox.generator
        generator.generateCGImageAsynchronously(
            for: CMTime(seconds: seconds[index], preferredTimescale: 600)
        ) { image, _, _ in
            withExtendedLifetime(generatorBox) {
                if let image {
                    Task { @MainActor in completion(image) }
                } else {
                    generateFrame(
                        with: generatorBox,
                        at: seconds,
                        index: index + 1,
                        completion: completion
                    )
                }
            }
        }
    }
}

private final class AVAssetImageGeneratorBox: @unchecked Sendable {
    let generator: AVAssetImageGenerator

    init(_ generator: AVAssetImageGenerator) {
        self.generator = generator
    }
}
