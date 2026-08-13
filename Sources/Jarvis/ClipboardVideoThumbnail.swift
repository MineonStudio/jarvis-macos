import AVFoundation
import AppKit
import Foundation

enum ClipboardVideoThumbnailGenerator {
    static func makePNGData(for url: URL) -> Data? {
        guard let image = makeCGImage(for: url) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .png, properties: [:])
    }

    static func makeCGImageAsync(for url: URL, completion: @escaping (CGImage?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let image = makeCGImage(for: url)
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    private static func makeCGImage(for url: URL) -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)

        // Prefer a frame shortly after the start so a fade-in does not leave
        // every card black, then fall back to the first frame for very short
        // or unusual containers.
        for seconds in [0.1, 0.0] {
            if let image = try? generator.copyCGImage(
                at: CMTime(seconds: seconds, preferredTimescale: 600),
                actualTime: nil
            ) {
                return image
            }
        }
        return nil
    }
}
