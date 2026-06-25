//
//  RecordingHistoryView.swift
//  whisperer
//

import SwiftUI
import SwiftData

struct RecordingHistoryView: View {
    @Query(sort: [SortDescriptor(\RecordingHistoryItem.timestamp, order: .reverse)]) private var recordings: [RecordingHistoryItem]
    @State private var searchText = ""

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
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredRecordings) { item in
                            RecordingHistoryRow(item: item)
                        }
                    }
                    .padding(16)
                }
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
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
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
