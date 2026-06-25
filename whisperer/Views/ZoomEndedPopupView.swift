//
//  ZoomEndedPopupView.swift
//  whisperer
//
//  Created by Roman Palkin on 04.02.2026.
//

import SwiftUI

/// Floating popup view shown when a Zoom meeting window closes during recording
struct ZoomEndedPopupView: View {
    let onStopRecording: () -> Void
    let onKeepRecording: () -> Void
    
    @State private var blinkOpacity: Double = 0.05
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "video.slash.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("Zoom Meeting Ended")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            // Content
            VStack(spacing: 12) {
                Text("A Zoom window was closed. Would you like to stop recording?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Buttons
                HStack(spacing: 12) {
                    Button("Keep Recording") {
                        onKeepRecording()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    Button("Stop Recording") {
                        onStopRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(blinkOpacity))
                .animation(
                    .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true),
                    value: blinkOpacity
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .onAppear {
            // Trigger the blink animation
            blinkOpacity = 0.15
        }
    }
}

#Preview {
    ZoomEndedPopupView(
        onStopRecording: { print("Stop recording") },
        onKeepRecording: { print("Keep recording") }
    )
    .padding(20)
}
