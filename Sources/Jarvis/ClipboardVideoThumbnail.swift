import AppKit
import AVFoundation
import Foundation

enum ClipboardVideoThumbnailGenerator {
    static func makeCGImageAsync(for url: URL, completion: @escaping (CGImage?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard FileManager.default.fileExists(atPath: url.path) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)

            // Prefer a frame shortly after the start so a fade-in does not
            // leave every card black, then fall back to the first frame for
            // very short or unusual containers.
            generateFrame(
                with: generator,
                at: [0.1, 0.0],
                index: 0,
                completion: completion
            )
        }
    }

    private static func generateFrame(
        with generator: AVAssetImageGenerator,
        at seconds: [Double],
        index: Int,
        completion: @escaping (CGImage?) -> Void
    ) {
        guard index < seconds.count else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        generator.generateCGImageAsynchronously(
            for: CMTime(seconds: seconds[index], preferredTimescale: 600)
        ) { image, _, _ in
            withExtendedLifetime(generator) {
                if let image {
                    DispatchQueue.main.async { completion(image) }
                } else {
                    generateFrame(
                        with: generator,
                        at: seconds,
                        index: index + 1,
                        completion: completion
                    )
                }
            }
        }
    }
}
