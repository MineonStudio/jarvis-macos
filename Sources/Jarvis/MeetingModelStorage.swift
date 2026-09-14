import FluidAudio
import Foundation

enum MeetingModelStorage {
    private static let paraformerDirectoryName = "paraformer-large-zh"

    static func availability(fileManager: FileManager = .default) -> MeetingModelAvailability {
        MeetingModelAvailability(
            speakerDiarizationReady: isOfflineDiarizationReady(fileManager: fileManager),
            chineseTranscriptionReady: isParaformerReady(fileManager: fileManager)
        )
    }

    private static func isOfflineDiarizationReady(fileManager: FileManager) -> Bool {
        let directory = MLModelConfigurationUtils.defaultModelsDirectory(for: .diarizer)
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

    private static func isParaformerReady(fileManager: FileManager) -> Bool {
        let directory = applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(paraformerDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        return ParaformerModels.modelsExist(at: directory, precision: .int8)
    }

    private static func applicationSupportDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
    }
}
