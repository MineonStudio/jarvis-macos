import Foundation
import Vision

enum ScreenshotTextRecognitionError: LocalizedError {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "截图无法读取，无法识别文字"
        case .noText:
            return "截图中未识别到文字"
        }
    }
}

enum ScreenshotTextRecognizer {
    private static let recognitionLanguages = [
        "zh-Hans",
        "zh-Hant",
        "en-US",
        "ja-JP",
        "ko-KR",
        "fr-FR",
        "es-ES"
    ]

    static func recognizeText(in imageData: Data) throws -> String {
        guard !imageData.isEmpty else {
            throw ScreenshotTextRecognitionError.invalidImage
        }

        var recognizedText = ""
        var recognitionError: Error?
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                recognitionError = error
                return
            }

            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            recognizedText = orderedText(from: observations)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supportedLanguages = (try? request.supportedRecognitionLanguages()) ?? []
        let configuredLanguages = recognitionLanguages.filter(supportedLanguages.contains)
        if !configuredLanguages.isEmpty {
            request.recognitionLanguages = configuredLanguages
        }

        do {
            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])
        } catch {
            throw ScreenshotTextRecognitionError.invalidImage
        }

        if let recognitionError {
            throw recognitionError
        }

        let text = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ScreenshotTextRecognitionError.noText
        }
        return text
    }

    private static func orderedText(from observations: [VNRecognizedTextObservation]) -> String {
        let lines = observations.compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(
                text: text,
                centerY: observation.boundingBox.midY,
                minX: observation.boundingBox.minX,
                height: observation.boundingBox.height
            )
        }

        var orderedLines: [[OCRLine]] = []
        for line in lines.sorted(by: { lhs, rhs in
            if abs(lhs.centerY - rhs.centerY) > max(lhs.height, rhs.height) * 0.6 {
                return lhs.centerY > rhs.centerY
            }
            return lhs.minX < rhs.minX
        }) {
            if let index = orderedLines.indices.first(where: { index in
                guard let first = orderedLines[index].first else { return false }
                return abs(first.centerY - line.centerY) <= max(first.height, line.height) * 0.6
            }) {
                orderedLines[index].append(line)
            } else {
                orderedLines.append([line])
            }
        }

        return orderedLines
            .map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    private struct OCRLine {
        let text: String
        let centerY: CGFloat
        let minX: CGFloat
        let height: CGFloat
    }
}
