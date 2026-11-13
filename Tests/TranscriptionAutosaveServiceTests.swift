import Foundation

@main
struct TranscriptionAutosaveServiceTests {
    static func main() throws {
        try filenameUsesRecordingTimestamp()
        try disabledAutosaveDoesNotCreateAFile()
        try savingAgainOverwritesTheExistingTranscript()
        print("TranscriptionAutosaveServiceTests: 3 passed")
    }

    private static func filenameUsesRecordingTimestamp() throws {
        let timestamp = try date("2026-09-16T14:05:09Z")
        let timeZone = try require(TimeZone(secondsFromGMT: 2 * 60 * 60))

        let filename = TranscriptionAutosaveService.filename(
            for: timestamp,
            timeZone: timeZone
        )

        try expectEqual(filename, "2026-09-16-16-05-09.md")
    }

    private static func disabledAutosaveDoesNotCreateAFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let savedURL = try TranscriptionAutosaveService().save(
            text: "This must not be saved",
            recordingTimestamp: Date(timeIntervalSince1970: 0),
            configuration: TranscriptionAutosaveConfiguration(
                isEnabled: false,
                directoryURL: directory
            ),
            timeZone: try require(TimeZone(secondsFromGMT: 0))
        )

        try expect(savedURL == nil, "Disabled autosave returned a file URL")
        try expect(
            !FileManager.default.fileExists(atPath: directory.path),
            "Disabled autosave created its output directory"
        )
    }

    private static func savingAgainOverwritesTheExistingTranscript() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let timestamp = try date("2026-09-16T14:05:09Z")
        let configuration = TranscriptionAutosaveConfiguration(
            isEnabled: true,
            directoryURL: directory
        )
        let service = TranscriptionAutosaveService()
        let timeZone = try require(TimeZone(secondsFromGMT: 0))

        let firstURL = try service.save(
            text: "old transcript",
            recordingTimestamp: timestamp,
            configuration: configuration,
            timeZone: timeZone
        )
        let secondURL = try service.save(
            text: "new transcript",
            recordingTimestamp: timestamp,
            configuration: configuration,
            timeZone: timeZone
        )

        try expectEqual(firstURL, secondURL)
        let savedURL = try require(secondURL)
        try expectEqual(savedURL.lastPathComponent, "2026-09-16-14-05-09.md")
        try expectEqual(try String(contentsOf: savedURL, encoding: .utf8), "new transcript")
    }

    private static func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try require(formatter.date(from: value))
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperer-autosave-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else {
            throw TestFailure(message: "Expected a non-nil value")
        }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TestFailure(message: message)
        }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
        try expect(actual == expected, "Expected \(expected), got \(actual)")
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
