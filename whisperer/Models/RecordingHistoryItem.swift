//
//  RecordingHistoryItem.swift
//  whisperer
//

import Foundation
import SwiftData

@Model
final class RecordingHistoryItem {
    var timestamp: Date
    var duration: TimeInterval
    private var audioFilePath: String

    var audioFileURL: URL {
        get { URL(fileURLWithPath: audioFilePath) }
        set { audioFilePath = newValue.path }
    }

    init(timestamp: Date = .now, duration: TimeInterval, audioFileURL: URL) {
        self.timestamp = timestamp
        self.duration = duration
        self.audioFilePath = audioFileURL.path
    }
}
