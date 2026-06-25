//
//  SettingsView.swift
//  whisperer
//
//  Created by Roman Palkin on 08.01.2026.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @EnvironmentObject var modelManager: FluidAudioModelManager
    @State private var isDirectoryWritable: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("Whisperer Settings")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Output Directory Section
                VStack(alignment: .leading, spacing: 8) {
                    Label("Output Directory", systemImage: "folder")
                        .font(.subheadline.weight(.medium))
                    
                    // Warning banner if directory is not writable
                    if !isDirectoryWritable {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Cannot write to this folder. Please select a different location.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: isDirectoryWritable ? "folder.fill" : "folder.fill.badge.questionmark")
                                .foregroundColor(isDirectoryWritable ? .secondary : .orange)
                            
                            Text(shortenPath(settings.outputDirectory))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(settings.outputDirectory)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isDirectoryWritable ? Color.primary.opacity(0.05) : Color.orange.opacity(0.1))
                        .cornerRadius(6)
                        
                        Button("Browse...") {
                            selectFolder()
                        }
                        .controlSize(.regular)
                    }
                    
                    HStack {
                        Spacer()
                        Button("Reset to Default") {
                            settings.resetOutputDirectory()
                            checkDirectoryWritable()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }

                Divider()

                // Transcription Section
                VStack(alignment: .leading, spacing: 8) {
                    Label("Transcription", systemImage: "text.bubble")
                        .font(.subheadline.weight(.medium))

                    FluidAudioModelCardView(manager: modelManager)

                    HStack {
                        Text("Language")
                            .font(.subheadline)
                        Spacer()
                        Picker("Language", selection: $settings.transcriptionLanguage) {
                            ForEach(AppSettings.transcriptionLanguages, id: \.code) { lang in
                                Text(lang.label).tag(lang.code)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
            }
            .padding()

            Spacer()
        }
        .frame(width: 380, height: 440)
        .onAppear {
            checkDirectoryWritable()
        }
    }
    
    private func checkDirectoryWritable() {
        settings.clearWritabilityCache()
        isDirectoryWritable = settings.isOutputDirectoryWritable()
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a folder to save your recordings"
        
        if let window = NSApp.windows.first(where: { $0.isKeyWindow }) {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    settings.outputDirectory = url.path
                    checkDirectoryWritable()
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                settings.outputDirectory = url.path
                checkDirectoryWritable()
            }
        }
    }
    
    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return path.replacingOccurrences(of: home, with: "~")
        }
        return path
    }
}

#Preview {
    SettingsView()
        .environmentObject(FluidAudioModelManager())
}