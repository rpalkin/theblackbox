//
//  AppSettings.swift
//  whisperer
//
//  Created by Roman Palkin on 08.01.2026.
//

import SwiftUI
internal import Combine

nonisolated protocol SecurityScopedBookmarkManaging {
    func bookmarkData(for url: URL) throws -> Data
    func resolveURL(from bookmarkData: Data) throws -> URL
}

private nonisolated struct SystemSecurityScopedBookmarkManager: SecurityScopedBookmarkManaging {
    func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveURL(from bookmarkData: Data) throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}

private enum AppSettingsError: LocalizedError {
    case transcriptionDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .transcriptionDirectoryUnavailable:
            return "The transcript folder is unavailable. Choose it again in Settings."
        }
    }
}

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private let bookmarkManager: any SecurityScopedBookmarkManaging
    private var transcriptionOutputDirectoryBookmark: Data?
    
    @Published var outputDirectory: String {
        didSet {
            defaults.set(outputDirectory, forKey: "outputDirectory")
            // Check if the new directory is writable
            _isOutputDirectoryWritable = nil
        }
    }

    @Published var transcriptionLanguage: String {
        didSet {
            defaults.set(transcriptionLanguage, forKey: "transcriptionLanguage")
        }
    }

    @Published var huggingFaceToken: String {
        didSet {
            defaults.set(huggingFaceToken, forKey: "huggingFaceToken")
        }
    }

    @Published var autosaveTranscriptionsEnabled: Bool {
        didSet {
            defaults.set(autosaveTranscriptionsEnabled, forKey: "autosaveTranscriptionsEnabled")
        }
    }

    @Published private(set) var transcriptionOutputDirectory: String {
        didSet {
            defaults.set(transcriptionOutputDirectory, forKey: "transcriptionOutputDirectory")
        }
    }

    static let transcriptionLanguages: [(code: String, label: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("de", "German"),
        ("fr", "French"),
        ("ru", "Russian"),
        ("pt", "Portuguese"),
        ("it", "Italian"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
    ]
    
    /// Cached result of directory writability check
    private var _isOutputDirectoryWritable: Bool?
    
    init(
        defaults: UserDefaults = .standard,
        bookmarkManager: any SecurityScopedBookmarkManaging = SystemSecurityScopedBookmarkManager()
    ) {
        self.defaults = defaults
        self.bookmarkManager = bookmarkManager
        
        // Initialize properties with values from UserDefaults or defaults
        let savedDir = defaults.string(forKey: "outputDirectory")
        let defaultDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Whisperer").path ?? ""
        
        if let savedDir = savedDir, !savedDir.isEmpty {
            self.outputDirectory = savedDir
        } else {
            self.outputDirectory = defaultDir
        }

        self.transcriptionLanguage = defaults.string(forKey: "transcriptionLanguage") ?? "auto"

        self.huggingFaceToken = defaults.string(forKey: "huggingFaceToken") ?? ""

        self.autosaveTranscriptionsEnabled = defaults.bool(forKey: "autosaveTranscriptionsEnabled")
        self.transcriptionOutputDirectory = defaults.string(forKey: "transcriptionOutputDirectory") ?? ""
        self.transcriptionOutputDirectoryBookmark = defaults.data(forKey: "transcriptionOutputDirectoryBookmark")

        // Create default directory if needed
        if self.outputDirectory == defaultDir {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: defaultDir), withIntermediateDirectories: true, attributes: nil)
        }
    }

    func setTranscriptionOutputDirectory(_ url: URL) throws {
        let bookmarkData = try bookmarkManager.bookmarkData(for: url)
        transcriptionOutputDirectoryBookmark = bookmarkData
        defaults.set(bookmarkData, forKey: "transcriptionOutputDirectoryBookmark")
        transcriptionOutputDirectory = url.path
    }

    func clearTranscriptionOutputDirectory() {
        transcriptionOutputDirectoryBookmark = nil
        defaults.removeObject(forKey: "transcriptionOutputDirectoryBookmark")
        transcriptionOutputDirectory = ""
    }

    func transcriptionAutosaveConfiguration() throws -> TranscriptionAutosaveConfiguration {
        guard autosaveTranscriptionsEnabled,
              !transcriptionOutputDirectory.isEmpty else {
            return TranscriptionAutosaveConfiguration(isEnabled: false, directoryURL: nil)
        }

        guard let bookmarkData = transcriptionOutputDirectoryBookmark else {
            throw AppSettingsError.transcriptionDirectoryUnavailable
        }

        do {
            let directoryURL = try bookmarkManager.resolveURL(from: bookmarkData)
            return TranscriptionAutosaveConfiguration(isEnabled: true, directoryURL: directoryURL)
        } catch {
            print("[AppSettings] Cannot resolve transcription output directory: \(error)")
            throw AppSettingsError.transcriptionDirectoryUnavailable
        }
    }
    
    func resetOutputDirectory() {
        if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let defaultDir = documentsDir.appendingPathComponent("Whisperer")
            outputDirectory = defaultDir.path
            
            // Create directory if it doesn't exist
            try? FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)
        }
    }
    
    /// Check if the output directory is writable
    /// Returns true if the app can write files to the output directory
    func isOutputDirectoryWritable() -> Bool {
        if let cached = _isOutputDirectoryWritable {
            return cached
        }
        
        let result = Self.checkDirectoryWritable(outputDirectory)
        _isOutputDirectoryWritable = result
        return result
    }
    
    /// Check if a specific directory is writable
    static func checkDirectoryWritable(_ path: String) -> Bool {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)
        
        // First, try to create the directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("[AppSettings] Cannot create directory: \(error)")
            return false
        }
        
        // Try to write a test file
        let testFileName = ".whisperer_write_test_\(UUID().uuidString)"
        let testFileURL = url.appendingPathComponent(testFileName)
        
        do {
            try "test".write(to: testFileURL, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFileURL)
            return true
        } catch {
            print("[AppSettings] Directory not writable: \(error)")
            return false
        }
    }
    
    /// Clear the cached writability check (call after user selects a new directory)
    func clearWritabilityCache() {
        _isOutputDirectoryWritable = nil
    }
}
