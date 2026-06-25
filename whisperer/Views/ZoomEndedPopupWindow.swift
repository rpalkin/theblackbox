//
//  ZoomEndedPopupWindow.swift
//  whisperer
//
//  Created by Roman Palkin on 04.02.2026.
//

import SwiftUI
import AppKit

/// Manages the floating popup window that appears when Zoom meeting ends
@MainActor
class PopupWindowManager {
    
    // MARK: - Singleton
    
    static let shared = PopupWindowManager()
    
    // MARK: - Properties
    
    private var popupPanel: NSPanel?
    private var onStopRecording: (() -> Void)?
    private var onKeepRecording: (() -> Void)?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Configuration
    
    /// Configure the callbacks for the popup buttons
    /// - Parameters:
    ///   - onStopRecording: Called when user clicks "Stop Recording"
    ///   - onKeepRecording: Called when user clicks "Keep Recording"
    func configure(
        onStopRecording: @escaping () -> Void,
        onKeepRecording: @escaping () -> Void
    ) {
        self.onStopRecording = onStopRecording
        self.onKeepRecording = onKeepRecording
    }
    
    // MARK: - Public Methods
    
    /// Show the popup below the menu bar
    func showPopup() {
        // Don't show multiple popups
        guard popupPanel == nil else {
            print("[PopupWindowManager] Popup already visible")
            return
        }
        
        print("[PopupWindowManager] Showing Zoom ended popup")
        
        // Create the SwiftUI view
        let popupView = ZoomEndedPopupView(
            onStopRecording: { [weak self] in
                self?.handleStopRecording()
            },
            onKeepRecording: { [weak self] in
                self?.handleKeepRecording()
            }
        )
        
        // Create an NSPanel for floating window behavior
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 150),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Configure panel properties
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        
        // Set content view with SwiftUI
        let hostingView = NSHostingView(rootView: popupView)
        panel.contentView = hostingView
        
        // Size to fit content
        hostingView.layoutSubtreeIfNeeded()
        let contentSize = hostingView.fittingSize
        panel.setContentSize(contentSize)
        
        // Position below menu bar icon (approximate center of screen, below menu bar)
        positionPanelBelowMenuBar(panel)
        
        // Store and show
        popupPanel = panel
        panel.orderFrontRegardless()
        
        // Play alert sound
        NSSound.beep()
    }
    
    /// Hide the popup
    func hidePopup() {
        print("[PopupWindowManager] Hiding Zoom ended popup")
        popupPanel?.close()
        popupPanel = nil
    }
    
    // MARK: - Private Methods
    
    private func positionPanelBelowMenuBar(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = screenFrame.height - visibleFrame.height - visibleFrame.origin.y
        
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        
        // Center horizontally, position just below menu bar with some padding
        let x = screenFrame.midX - (panelWidth / 2)
        let y = screenFrame.height - menuBarHeight - panelHeight - 10
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func handleStopRecording() {
        hidePopup()
        onStopRecording?()
    }
    
    private func handleKeepRecording() {
        hidePopup()
        onKeepRecording?()
    }
}
