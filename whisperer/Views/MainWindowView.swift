//
//  MainWindowView.swift
//  whisperer
//

import SwiftUI
import AppKit
internal import Combine

enum MainWindowTab: String, Hashable, Identifiable, CaseIterable {
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class MainWindowNavigation: ObservableObject {
    static let shared = MainWindowNavigation()
    @Published var selectedTab: MainWindowTab = .history
}

struct MainWindowView: View {
    @ObservedObject private var navigation = MainWindowNavigation.shared
    @State private var selectedTab: MainWindowTab = MainWindowNavigation.shared.selectedTab
    let transcriptionService: FluidAudioTranscriptionService

    var body: some View {
        NavigationSplitView {
            List(MainWindowTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch selectedTab {
            case .history:
                RecordingHistoryView(transcriptionService: transcriptionService)
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear { selectedTab = navigation.selectedTab }
        .onChange(of: navigation.selectedTab) { _, new in
            if selectedTab != new { selectedTab = new }
        }
        .onChange(of: selectedTab) { _, new in
            if navigation.selectedTab != new { navigation.selectedTab = new }
        }
    }
}

@MainActor
enum DockIconController {
    private static var didInstall = false

    static func installCloseObserverIfNeeded() {
        guard !didInstall else { return }
        didInstall = true
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in
                guard isMainWindow(window) else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    static func openMain() {
        installCloseObserverIfNeeded()
        NSApp.setActivationPolicy(.regular)
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue.contains("main") == true { return true }
        return window.title == "Whisperer"
    }
}
