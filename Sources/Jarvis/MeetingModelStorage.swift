import FluidAudio
import Foundation

enum MeetingModelStorage {
    static func availability(fileManager: FileManager = .default) -> MeetingModelAvailability {
        MeetingModelAvailability(
            speakerDiarizationReady: isOfflineDiarizationReady(fileManager: fileManager),
            chineseTranscriptionReady: false
        )
    }

    static func removeModel(
        for stage: MeetingModelPreparationStage,
        fileManager: FileManager = .default
    ) throws {
        guard stage == .speakerDiarization else { return }
        let directory = diarizerDirectory
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private static var diarizerDirectory: URL {
        MLModelConfigurationUtils.defaultModelsDirectory(for: .diarizer)
    }

    private static func isOfflineDiarizationReady(fileManager: FileManager) -> Bool {
        let directory = diarizerDirectory
        return ModelNames.OfflineDiarizer.requiredModels.allSatisfy { name in
            let url = directory.appendingPathComponent(name, isDirectory: name.hasSuffix(".mlmodelc"))
            if name.hasSuffix(".mlmodelc") {
                return fileManager.fileExists(
                    atPath: url.appendingPathComponent("coremldata.bin").path
                )
            }
            return fileManager.fileExists(atPath: url.path)
        }
    }
}
