//
//  AppSettings.swift
//  whisperer
//
//  Created by Roman Palkin on 08.01.2026.
//

import SwiftUI
internal import Combine

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @Published var outputDirectory: String {
        didSet {
            UserDefaults.standard.set(outputDirectory, forKey: "outputDirectory")
            // Check if the new directory is writable
            _isOutputDirectoryWritable = nil
        }
    }

    @Published var transcriptionLanguage: String {
        didSet {
            UserDefaults.standard.set(transcriptionLanguage, forKey: "transcriptionLanguage")
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
    
    init() {
        let defaults = UserDefaults.standard
        
        // Initialize properties with values from UserDefaults or defaults
        let savedDir = defaults.string(forKey: "outputDirectory")
        let defaultDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Whisperer").path ?? ""
        
        if let savedDir = savedDir, !savedDir.isEmpty {
            self.outputDirectory = savedDir
        } else {
            self.outputDirectory = defaultDir
        }

        self.transcriptionLanguage = defaults.string(forKey: "transcriptionLanguage") ?? "auto"

        // Create default directory if needed
        if self.outputDirectory == defaultDir {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: defaultDir), withIntermediateDirectories: true, attributes: nil)
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
