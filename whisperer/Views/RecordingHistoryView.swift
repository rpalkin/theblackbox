//
//  RecordingHistoryView.swift
//  whisperer
//

import SwiftUI
import SwiftData
internal import AVFoundation
internal import UniformTypeIdentifiers

struct RecordingHistoryView: View {
    @Query(sort: [SortDescriptor(\RecordingHistoryItem.timestamp, order: .reverse)]) private var recordings: [RecordingHistoryItem]
    @State private var searchText = ""
    @State private var loadErrorMessage: String?
    @State private var expandedId: PersistentIdentifier?
    @EnvironmentObject var modelManager: FluidAudioModelManager
    let transcriptionService: FluidAudioTranscriptionService

    init(transcriptionService: FluidAudioTranscriptionService) {
        self.transcriptionService = transcriptionService
    }

    private var filteredRecordings: [RecordingHistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recordings }

        return recordings.filter { item in
            let url = item.audioFileURL
            let searchableText = [
                Self.dateFormatter.string(from: item.timestamp),
                Self.timeFormatter.string(from: item.timestamp),
                Self.durationFormatter.string(from: item.duration) ?? "",
                url.lastPathComponent,
                url.path
            ].joined(separator: " ").lowercased()

            return searchableText.contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if filteredRecordings.isEmpty {
                emptyState
            } else {
                Form {
                    ForEach(filteredRecordings) { item in
                        Section {
                            RecordingHistoryRow(
                                item: item,
                                isExpanded: expandedId == item.persistentModelID,
                                modelManager: modelManager,
                                transcriptionService: transcriptionService,
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedId = expandedId == item.persistentModelID ? nil : item.persistentModelID
                                    }
                                }
                            )
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording History")
                        .font(.title2.weight(.semibold))
                    Text("\(recordings.count) saved recording\(recordings.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    presentLoadPanel()
                } label: {
                    Label("Load", systemImage: "square.and.arrow.down")
                }
            }

            if let loadErrorMessage {
                Text(loadErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by date, file name, or path", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "clock.badge.questionmark" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No recordings yet" : "No matching recordings")
                .font(.headline)
            Text(searchText.isEmpty ? "Completed recordings will appear here." : "Try a different date, file name, or path.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func presentLoadPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        panel.message = "Select audio recordings to add to history"
        panel.prompt = "Load"

        guard panel.runModal() == .OK else { return }

        let urls = panel.urls
        Task { await loadFiles(urls) }
    }

    @MainActor
    private func loadFiles(_ urls: [URL]) async {
        var failures: [String] = []
        for url in urls {
            do {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                let timestamp = (try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date) ?? .now
                try RecordingHistoryStore.insertRecording(
                    audioFileURL: url,
                    duration: seconds.isFinite ? seconds : 0,
                    timestamp: timestamp
                )
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        loadErrorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
}

private struct RecordingHistoryRow: View {
    let item: RecordingHistoryItem
    let isExpanded: Bool
    @ObservedObject var modelManager: FluidAudioModelManager
    @StateObject private var viewModel: TranscriptionRowViewModel
    let onToggleExpand: () -> Void

    init(
        item: RecordingHistoryItem,
        isExpanded: Bool,
        modelManager: FluidAudioModelManager,
        transcriptionService: FluidAudioTranscriptionService,
        onToggleExpand: @escaping () -> Void
    ) {
        self.item = item
        self.isExpanded = isExpanded
        self.modelManager = modelManager
        self.onToggleExpand = onToggleExpand
        _viewModel = StateObject(wrappedValue: TranscriptionRowViewModel(
            transcriptionService: transcriptionService,
            modelManager: modelManager
        ))
    }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: item.audioFileURL.path)
    }

    private var transcribeButtonLabel: String {
        guard viewModel.isTranscribingThisRow else { return "Transcribe" }
        return modelManager.downloadProgress != nil ? "Downloading model…" : "Transcribing…"
    }

    private var transcribeButtonDisabled: Bool {
        !fileExists || modelManager.isTranscribing
    }

    private var transcribeButtonTooltip: String {
        if !fileExists { return "Recording file not found" }
        if modelManager.isTranscribing && !viewModel.isTranscribingThisRow {
            return "Another transcription is running"
        }
        return ""
    }

    private var hasTranscript: Bool {
        if let t = item.text_me, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "doc.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.audioFileURL.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(Self.durationFormatter.string(from: item.duration) ?? "0s")
                            .font(.system(.caption, design: .monospaced).weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text("\(Self.dateFormatter.string(from: item.timestamp)) at \(Self.timeFormatter.string(from: item.timestamp))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    .padding(.top, 14)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(item.audioFileURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.audioFileURL])
                        }
                        .buttonStyle(.link)
                        .font(.caption)

                        Button(transcribeButtonLabel) {
                            viewModel.transcribe(item: item)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .disabled(transcribeButtonDisabled)
                        .help(transcribeButtonTooltip)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let dialog = item.text_me, !dialog.isEmpty {
                        TranscriptionTextView(label: "Transcript", text: dialog)
                    } else {
                        Text("No transcription yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
}

private struct TranscriptionTextView: View {
    let label: String
    let text: String

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy transcription", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .disabled(isEmpty)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
