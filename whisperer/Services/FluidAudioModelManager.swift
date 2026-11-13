//
//  FluidAudioModelManager.swift
//  whisperer
//

import Foundation
internal import Combine
import FluidAudio

enum ModelDownloadPhase: Equatable {
    case listing
    case downloading
    case compiling

    init(_ phase: DownloadUtils.DownloadPhase) {
        switch phase {
        case .listing:
            self = .listing
        case .downloading:
            self = .downloading
        case .compiling:
            self = .compiling
        }
    }

    var displayName: String {
        switch self {
        case .listing:
            return "Listing files"
        case .downloading:
            return "Downloading"
        case .compiling:
            return "Compiling"
        }
    }
}

enum FluidAudioModelManagerError: LocalizedError {
    case operationInProgress
    case transcriptionInProgress
    case modelUnavailable(String)
    case stalled
    case cancelled

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            return "Model download is already in progress."
        case .transcriptionInProgress:
            return "Cannot delete the model while a transcription is in progress."
        case .modelUnavailable(let message):
            return message
        case .stalled:
            return "Download stalled while listing files. Check your network and try again."
        case .cancelled:
            return "Model download was cancelled."
        }
    }
}

@MainActor
final class FluidAudioModelManager: ObservableObject {
    @Published private(set) var isInstalled: Bool
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var currentPhase: ModelDownloadPhase?
    @Published var isTranscribing: Bool = false
    @Published var lastError: String?

    private let fileManager: FileManager
    private let modelVersion: AsrModelVersion
    private var cachedAsrManager: AsrManager?
    private var loadingTask: Task<AsrManager, Error>?
    private var watchdogTask: Task<Void, Never>?
    private var lastProgressAt: Date = .distantPast
    private let stallTimeout: TimeInterval = 120

    init(
        fileManager: FileManager = .default,
        modelVersion: AsrModelVersion = .v3
    ) {
        self.fileManager = fileManager
        self.modelVersion = modelVersion

        let cacheDirectory = AsrModels.defaultCacheDirectory(for: modelVersion)
        self.isInstalled = Self.modelsExist(at: cacheDirectory, version: modelVersion)
    }

    private func configureHuggingFaceToken() {
        let token = AppSettings.shared.huggingFaceToken
        if token.isEmpty {
            unsetenv("HF_TOKEN")
        } else {
            setenv("HF_TOKEN", token, 1)
        }
    }

    func downloadAndLoadIfNeeded() async {
        configureHuggingFaceToken()
        lastError = nil

        if cachedAsrManager != nil, verifyInstalled() {
            return
        }

        if let loadingTask {
            do {
                cachedAsrManager = try await loadingTask.value
                isInstalled = verifyInstalled()
            } catch {
                cachedAsrManager = nil
                isInstalled = verifyInstalled()
                lastError = Self.userReadableMessage(from: error)
            }
            return
        }

        downloadProgress = 0
        currentPhase = .listing
        lastProgressAt = Date()

        let loadingTask = Task<AsrManager, Error> {
            let models = try await AsrModels.downloadAndLoad(
                version: modelVersion,
                progressHandler: { progress in
                    Task { @MainActor [weak self] in
                        self?.apply(progress: progress)
                    }
                }
            )
            return AsrManager(models: models)
        }

        self.loadingTask = loadingTask
        startWatchdog(for: loadingTask)

        do {
            cachedAsrManager = try await loadingTask.value
            isInstalled = verifyInstalled()
            lastError = nil
        } catch is CancellationError {
            cachedAsrManager = nil
            isInstalled = verifyInstalled()
            if lastError == nil {
                lastError = FluidAudioModelManagerError.cancelled.localizedDescription
            }
        } catch {
            cachedAsrManager = nil
            isInstalled = verifyInstalled()
            lastError = Self.userReadableMessage(from: error)
        }

        watchdogTask?.cancel()
        watchdogTask = nil
        self.loadingTask = nil
        downloadProgress = nil
        currentPhase = nil
    }

    func cancel() {
        guard let task = loadingTask else { return }
        lastError = FluidAudioModelManagerError.cancelled.localizedDescription
        task.cancel()
        watchdogTask?.cancel()
    }

    private func startWatchdog(for task: Task<AsrManager, Error>) {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                guard let self, !task.isCancelled else { return }
                if Date().timeIntervalSince(self.lastProgressAt) > self.stallTimeout {
                    self.lastError = FluidAudioModelManagerError.stalled.localizedDescription
                    task.cancel()
                    return
                }
            }
        }
    }

    func deleteCache() async {
        lastError = nil

        guard !isTranscribing else {
            lastError = FluidAudioModelManagerError.transcriptionInProgress.localizedDescription
            return
        }

        guard loadingTask == nil, downloadProgress == nil else {
            lastError = FluidAudioModelManagerError.operationInProgress.localizedDescription
            return
        }

        let cacheDirectory = modelCacheDirectory
        guard fileManager.fileExists(atPath: cacheDirectory.path) else {
            cachedAsrManager = nil
            isInstalled = false
            return
        }

        do {
            let cachedItems = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )

            for itemURL in cachedItems {
                try fileManager.removeItem(at: itemURL)
            }

            cachedAsrManager = nil
            isInstalled = verifyInstalled()
        } catch {
            lastError = Self.userReadableMessage(from: error)
            isInstalled = verifyInstalled()
        }
    }

    @discardableResult
    func verifyInstalled() -> Bool {
        let installed = Self.modelsExist(at: modelCacheDirectory, version: modelVersion)
        isInstalled = installed

        if !installed {
            cachedAsrManager = nil
        }

        return installed
    }

    func languageHint(from settingValue: String) -> String? {
        let trimmedValue = settingValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue == "auto" {
            return nil
        }

        return Self.allowedLanguageCodes.contains(trimmedValue) ? trimmedValue : nil
    }

    func borrowManager() async throws -> AsrManager {
        if cachedAsrManager == nil || !verifyInstalled() {
            await downloadAndLoadIfNeeded()
        }

        guard let cachedAsrManager else {
            throw FluidAudioModelManagerError.modelUnavailable(
                lastError ?? "Speech model is not available."
            )
        }

        return cachedAsrManager
    }

    private var modelCacheDirectory: URL {
        AsrModels.defaultCacheDirectory(for: modelVersion)
    }

    private func apply(progress: DownloadUtils.DownloadProgress) {
        downloadProgress = min(max(progress.fractionCompleted, 0), 1)
        currentPhase = ModelDownloadPhase(progress.phase)
        lastProgressAt = Date()
    }

    private static let allowedLanguageCodes: Set<String> = [
        "en", "es", "de", "fr", "ru", "pt", "it", "nl", "pl"
    ]

    private static func modelsExist(at directory: URL, version: AsrModelVersion) -> Bool {
        AsrModels.modelsExist(at: directory, version: version)
    }

    private static func userReadableMessage(from error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            return message
        }

        return "Failed to prepare the transcription model."
    }
}
