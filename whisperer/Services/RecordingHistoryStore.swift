//
//  RecordingHistoryStore.swift
//  whisperer
//

import Foundation
import SwiftData

enum RecordingHistoryStore {
    static let storeFileName = "RecordingHistory.store"

    static let sharedModelContainer: ModelContainer = {
        do {
            return try makeModelContainer()
        } catch {
            fatalError("Failed to create recording history store: \(error)")
        }
    }()

    static var storeDirectoryURL: URL {
        get throws {
            let fileManager = FileManager.default
            let applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directoryURL = applicationSupportURL.appendingPathComponent("Whisperer", isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            return directoryURL
        }
    }

    static var storeURL: URL {
        get throws {
            try storeDirectoryURL.appendingPathComponent(storeFileName)
        }
    }

    static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([RecordingHistoryItem.self])
        let configuration = ModelConfiguration(schema: schema, url: try storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    static func insertRecording(audioFileURL: URL, duration: TimeInterval, timestamp: Date = .now) throws {
        let container = sharedModelContainer
        let item = RecordingHistoryItem(timestamp: timestamp, duration: duration, audioFileURL: audioFileURL)
        container.mainContext.insert(item)
        try container.mainContext.save()
    }
}
