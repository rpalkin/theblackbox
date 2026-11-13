import Foundation

@main
struct AppSettingsTranscriptionAutosaveTests {
    @MainActor
    static func main() throws {
        let suiteName = "info.palkin.whisperer.tests.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bookmarkManager = BookmarkManagerStub()
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcripts", isDirectory: true)

        let initialSettings = AppSettings(
            defaults: defaults,
            bookmarkManager: bookmarkManager
        )
        initialSettings.autosaveTranscriptionsEnabled = true

        let emptyFolderConfiguration = try initialSettings.transcriptionAutosaveConfiguration()
        try expect(
            !emptyFolderConfiguration.isEnabled,
            "An empty folder path did not disable autosave"
        )

        try initialSettings.setTranscriptionOutputDirectory(folderURL)
        let savedConfiguration = try initialSettings.transcriptionAutosaveConfiguration()
        try expect(savedConfiguration.isEnabled, "A selected folder did not enable the configuration")
        try expectEqual(savedConfiguration.directoryURL, folderURL)

        let restoredSettings = AppSettings(
            defaults: defaults,
            bookmarkManager: bookmarkManager
        )
        let restoredConfiguration = try restoredSettings.transcriptionAutosaveConfiguration()
        try expect(restoredConfiguration.isEnabled, "The autosave flag was not restored")
        try expectEqual(restoredConfiguration.directoryURL, folderURL)
        try expectEqual(restoredSettings.transcriptionOutputDirectory, folderURL.path)

        restoredSettings.clearTranscriptionOutputDirectory()
        let clearedConfiguration = try restoredSettings.transcriptionAutosaveConfiguration()
        try expect(
            !clearedConfiguration.isEnabled,
            "Clearing the folder did not disable autosave"
        )
        try expectEqual(restoredSettings.transcriptionOutputDirectory, "")

        defaults.set(true, forKey: "autosaveTranscriptionsEnabled")
        defaults.set(folderURL.path, forKey: "transcriptionOutputDirectory")
        defaults.removeObject(forKey: "transcriptionOutputDirectoryBookmark")
        let settingsWithMissingBookmark = AppSettings(
            defaults: defaults,
            bookmarkManager: bookmarkManager
        )
        try expectThrows {
            _ = try settingsWithMissingBookmark.transcriptionAutosaveConfiguration()
        }

        print("AppSettingsTranscriptionAutosaveTests: 1 passed")
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

    private static func expectThrows(_ operation: () throws -> Void) throws {
        do {
            try operation()
            throw TestFailure(message: "Expected operation to throw")
        } catch is TestFailure {
            throw TestFailure(message: "Expected operation to throw")
        } catch {
            return
        }
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}

private struct BookmarkManagerStub: SecurityScopedBookmarkManaging {
    func bookmarkData(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolveURL(from bookmarkData: Data) throws -> URL {
        let path = try require(String(data: bookmarkData, encoding: .utf8))
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func require<T>(_ value: T?) throws -> T {
        guard let value else {
            throw BookmarkStubError.invalidData
        }
        return value
    }

    private enum BookmarkStubError: Error {
        case invalidData
    }
}
