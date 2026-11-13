import Foundation

nonisolated struct TranscriptionAutosaveConfiguration: Sendable {
    let isEnabled: Bool
    let directoryURL: URL?
}

nonisolated struct TranscriptionAutosaveService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    func save(
        text: String,
        recordingTimestamp: Date,
        configuration: TranscriptionAutosaveConfiguration,
        timeZone: TimeZone = .current
    ) throws -> URL? {
        guard configuration.isEnabled, let directoryURL = configuration.directoryURL else {
            return nil
        }

        let isAccessingSecurityScopedResource = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = directoryURL.appendingPathComponent(
            Self.filename(for: recordingTimestamp, timeZone: timeZone),
            isDirectory: false
        )
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    static func filename(for timestamp: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.string(from: timestamp) + ".md"
    }
}
