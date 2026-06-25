//
//  TranscriptionRowViewModel.swift
//  whisperer
//

import Foundation
internal import Combine

@MainActor
final class TranscriptionRowViewModel: ObservableObject {
    @Published private(set) var isTranscribingThisRow = false
    @Published private(set) var errorMessage: String?

    private let transcriptionService: FluidAudioTranscriptionService
    private let modelManager: FluidAudioModelManager

    init(
        transcriptionService: FluidAudioTranscriptionService,
        modelManager: FluidAudioModelManager
    ) {
        self.transcriptionService = transcriptionService
        self.modelManager = modelManager
    }

    func transcribe(item: RecordingHistoryItem) {
        isTranscribingThisRow = true
        errorMessage = nil
        Task {
            do {
                let language = modelManager.languageHint(from: AppSettings.shared.transcriptionLanguage)
                try await transcriptionService.transcribe(item: item, languageHint: language)
            } catch {
                errorMessage = error.localizedDescription
            }
            isTranscribingThisRow = false
        }
    }
}
