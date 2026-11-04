import SwiftUI

/// Rolling, revisable text at the chosen font size. Layout wraps instead of splitting
/// recognition text, and following can be paused to review earlier visible content.
struct SubtitleView: View {
    @ObservedObject var session: CaptionSession
    @ObservedObject var settings: AppSettings
    @State private var followsLive = true

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 10) {
                if !settings.overlayIsClickThrough {
                    HStack {
                        if settings.isOverlayLocked {
                            Text("Live captions").font(.caption.weight(.semibold))
                        } else {
                            OverlayDragHandle()
                                .overlay {
                                    Label("Drag to move", systemImage: "hand.draw")
                                        .font(.caption).allowsHitTesting(false)
                                }
                                .frame(maxWidth: .infinity)
                                .help("Drag here to reposition captions")
                        }
                        Spacer()
                        Toggle("Follow live", isOn: $followsLive)
                            .toggleStyle(.switch).controlSize(.mini).font(.caption)
                    }
                    .frame(height: 22)
                    .foregroundStyle(.white.opacity(0.85))
                }
                CaptionTextView(
                    text: session.displayCaptions.isEmpty ? "Live captions appear here." :
                        session.displayCaptions.map(\.text).joined(separator: "\n"),
                    fontSize: settings.fontSize,
                    followsLive: settings.overlayIsClickThrough || followsLive,
                    showsScrollIndicator: !settings.overlayIsClickThrough)
                    .frame(height: CaptionTextMetrics(fontSize: settings.fontSize)
                        .viewportHeight(for: settings.maximumCaptionLines))
                    .onChange(of: settings.overlayIsClickThrough) { _, enabled in
                        if enabled { followsLive = true }
                    }
            }
            .padding(.trailing, 32)
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(.black.opacity(settings.opacity), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
