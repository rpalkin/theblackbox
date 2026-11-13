//
//  FluidAudioModelCardView.swift
//  whisperer
//

import SwiftUI

struct FluidAudioModelCardView: View {
    @ObservedObject var manager: FluidAudioModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Parakeet TDT v3", systemImage: "waveform")
                .font(.subheadline.weight(.medium))

            if let error = manager.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
            }

            if let progress = manager.downloadProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                    HStack {
                        if let phase = manager.currentPhase {
                            Text(phase.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Cancel") {
                            manager.cancel()
                        }
                        .controlSize(.small)
                    }
                }
            } else if manager.isInstalled {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Model installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete") {
                        Task { await manager.deleteCache() }
                    }
                    .disabled(manager.downloadProgress != nil || manager.isTranscribing)
                    .controlSize(.small)
                }
            } else {
                HStack {
                    Text("Model not installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Download") {
                        Task { await manager.downloadAndLoadIfNeeded() }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    FluidAudioModelCardView(manager: FluidAudioModelManager())
        .padding()
        .frame(width: 340)
}
