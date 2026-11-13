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
    private let autosaveService: TranscriptionAutosaveService
    private var isTranscriptionRunning = false
    private var transcriptionWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        manager: FluidAudioModelManager,
        extractor: AudioTrackExtractor = AudioTrackExtractor(),
        autosaveService: TranscriptionAutosaveService = TranscriptionAutosaveService()
    ) {
        self.manager = manager
        self.extractor = extractor
        self.autosaveService = autosaveService
    }

    func transcribe(item: RecordingHistoryItem, languageHint: String?) async throws {
        await waitForTranscriptionSlot()

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

            let micWords = try await transcribeTrack(
                samples: micSamples,
                asrManager: asrManager,
                language: language
            )
            let systemWords = try await transcribeTrack(
                samples: systemSamples,
                asrManager: asrManager,
                language: language
            )

            let dialog = Self.buildDialog(
                micChunks: Self.chunkWords(micWords, label: "Me"),
                systemChunks: Self.chunkWords(systemWords, label: "System")
            )

            try await MainActor.run {
                try RecordingHistoryStore.updateTranscription(
                    item: item,
                    textMe: dialog,
                    textAudio: ""
                )
            }

            do {
                let configuration = try await MainActor.run {
                    try AppSettings.shared.transcriptionAutosaveConfiguration()
                }
                if let savedURL = try autosaveService.save(
                    text: dialog,
                    recordingTimestamp: item.timestamp,
                    configuration: configuration
                ) {
                    print("[FluidAudioTranscriptionService] Transcript saved to: \(savedURL.path)")
                }
            } catch {
                throw FluidAudioTranscriptionError.failed(
                    "Transcription completed, but the Markdown file could not be saved: \(error.localizedDescription)"
                )
            }
            await completeTranscriptionSlot()
        } catch {
            let message = Self.userReadableMessage(from: error)
            await MainActor.run {
                manager.lastError = message
            }
            await completeTranscriptionSlot()
            throw FluidAudioTranscriptionError.failed(message)
        }
    }

    private func waitForTranscriptionSlot() async {
        guard isTranscriptionRunning else {
            isTranscriptionRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            transcriptionWaiters.append(continuation)
        }
    }

    private func completeTranscriptionSlot() async {
        let hasWaitingTranscription = releaseTranscriptionSlot()
        await MainActor.run {
            manager.isTranscribing = hasWaitingTranscription
        }
    }

    private func releaseTranscriptionSlot() -> Bool {
        guard !transcriptionWaiters.isEmpty else {
            isTranscriptionRunning = false
            return false
        }

        transcriptionWaiters.removeFirst().resume()
        return true
    }

    private func transcribeTrack(
        samples: [Float],
        asrManager: AsrManager,
        language: Language?
    ) async throws -> [WordTiming] {
        guard !samples.isEmpty else {
            return []
        }

        var state = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            samples,
            decoderState: &state,
            language: language
        )

        guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return [] }
            return [WordTiming(word: trimmed, startTime: 0, endTime: result.duration)]
        }

        return buildWordTimings(from: tokenTimings)
    }

    private struct DialogChunk {
        let label: String
        let text: String
        let start: TimeInterval
    }

    private static let utteranceGapThreshold: TimeInterval = 1.0

    private static func chunkWords(_ words: [WordTiming], label: String) -> [DialogChunk] {
        guard !words.isEmpty else { return [] }

        var chunks: [DialogChunk] = []
        var currentWords: [String] = []
        var currentStart: TimeInterval = words[0].startTime
        var previousEnd: TimeInterval = words[0].startTime

        for word in words {
            if !currentWords.isEmpty && word.startTime - previousEnd > utteranceGapThreshold {
                chunks.append(DialogChunk(
                    label: label,
                    text: currentWords.joined(separator: " "),
                    start: currentStart
                ))
                currentWords.removeAll(keepingCapacity: true)
                currentStart = word.startTime
            }
            currentWords.append(word.word)
            previousEnd = word.endTime
        }

        if !currentWords.isEmpty {
            chunks.append(DialogChunk(
                label: label,
                text: currentWords.joined(separator: " "),
                start: currentStart
            ))
        }

        return chunks
    }

    private static func buildDialog(micChunks: [DialogChunk], systemChunks: [DialogChunk]) -> String {
        let merged = (micChunks + systemChunks).sorted { $0.start < $1.start }
        return merged
            .map { "**\($0.label)**: \($0.text)" }
            .joined(separator: "\n\n")
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
