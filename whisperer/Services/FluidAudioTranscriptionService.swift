//
//  FluidAudioTranscriptionService.swift
//  whisperer
//

import Foundation
import FluidAudio

enum FluidAudioTranscriptionError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

actor FluidAudioTranscriptionService {
    private let manager: FluidAudioModelManager
    private let extractor: AudioTrackExtractor

    init(
        manager: FluidAudioModelManager,
        extractor: AudioTrackExtractor = AudioTrackExtractor()
    ) {
        self.manager = manager
        self.extractor = extractor
    }

    func transcribe(item: RecordingHistoryItem, languageHint: String?) async throws {
        await MainActor.run {
            manager.lastError = nil
            manager.isTranscribing = true
        }

        do {
            let asrManager = try await manager.borrowManager()
            let language = language(from: languageHint)
            let audioFileURL = item.audioFileURL

            let micSamples = try await extractor.extract(url: audioFileURL, role: .microphone)
            let systemSamples = try await extractor.extract(url: audioFileURL, role: .systemAudio)

            let textMic = try await transcribeTrack(
                samples: micSamples,
                asrManager: asrManager,
                language: language
            )
            let textSystem = try await transcribeTrack(
                samples: systemSamples,
                asrManager: asrManager,
                language: language
            )

            try await MainActor.run {
                try RecordingHistoryStore.updateTranscription(
                    item: item,
                    textMe: textMic,
                    textAudio: textSystem
                )
                manager.isTranscribing = false
            }
        } catch {
            let message = Self.userReadableMessage(from: error)
            await MainActor.run {
                manager.lastError = message
                manager.isTranscribing = false
            }
            throw FluidAudioTranscriptionError.failed(message)
        }
    }

    private func transcribeTrack(
        samples: [Float],
        asrManager: AsrManager,
        language: Language?
    ) async throws -> String {
        guard !samples.isEmpty else {
            return ""
        }

        var state = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            samples,
            decoderState: &state,
            language: language
        )
        return result.text
    }

    private func language(from languageHint: String?) -> Language? {
        guard let languageHint else {
            return nil
        }

        return Language(rawValue: languageHint)
    }

    private static func userReadableMessage(from error: Error) -> String {
        if let transcriptionError = error as? FluidAudioTranscriptionError,
           let message = transcriptionError.errorDescription,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            return message
        }

        return "Transcription failed."
    }
}
