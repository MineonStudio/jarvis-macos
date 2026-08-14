import Foundation
import Vision

enum ScreenshotTextRecognitionError: LocalizedError {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "截图无法读取，无法识别文字"
        case .noText:
            "截图中未识别到文字"
        }
    }
}

struct ScreenshotOCRBlock: Equatable {
    let text: String
    let boundingBox: CGRect
}

struct ScreenshotOCRResult: Equatable {
    let text: String
    let blocks: [ScreenshotOCRBlock]
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
        try recognize(in: imageData).text
    }

    static func recognize(in imageData: Data) throws -> ScreenshotOCRResult {
        guard !imageData.isEmpty else {
            throw ScreenshotTextRecognitionError.invalidImage
        }

        var recognitionResult: ScreenshotOCRResult?
        var recognitionError: Error?
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                recognitionError = error
                return
            }

            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let blocks = orderedBlocks(from: observations)
            recognitionResult = ScreenshotOCRResult(
                text: blocks.map(\.text).joined(separator: "\n"),
                blocks: blocks
            )
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

        guard let result = recognitionResult,
              !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ScreenshotTextRecognitionError.noText
        }
        return result
    }

    private static func orderedBlocks(from observations: [VNRecognizedTextObservation]) -> [ScreenshotOCRBlock] {
        let lines = observations.compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(
                text: text,
                boundingBox: observation.boundingBox
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

        return orderedLines.compactMap { group in
            let sortedGroup = group.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            guard let first = sortedGroup.first else { return nil }
            let boundingBox = sortedGroup.dropFirst().reduce(first.boundingBox) { result, line in
                result.union(line.boundingBox)
            }
            return ScreenshotOCRBlock(
                text: sortedGroup.map(\.text).joined(separator: " "),
                boundingBox: boundingBox
            )
        }
    }

    private struct OCRLine {
        let text: String
        let boundingBox: CGRect

        var centerY: CGFloat {
            boundingBox.midY
        }

        var minX: CGFloat {
            boundingBox.minX
        }

        var height: CGFloat {
            boundingBox.height
        }
    }
}
