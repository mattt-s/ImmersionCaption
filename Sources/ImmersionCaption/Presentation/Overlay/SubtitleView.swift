import SwiftUI

/// Rolling, revisable text at the chosen font size. Layout wraps instead of splitting
/// recognition text, and following can be paused to review earlier visible content.
struct SubtitleView: View {
    @ObservedObject var session: CaptionSession
    @ObservedObject var settings: AppSettings
    @State private var followsLive = true
    private let bottomAnchor = "latest-caption"

    var body: some View {
        VStack {
            if settings.position != .top { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Live captions").font(.caption.weight(.semibold))
                    Spacer()
                    Toggle("Follow live", isOn: $followsLive)
                        .toggleStyle(.switch).controlSize(.mini).font(.caption)
                }
                .foregroundStyle(.white.opacity(0.85))
                ScrollViewReader { reader in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            if session.displayCaptions.isEmpty {
                                Text("Live captions appear here.")
                            }
                            ForEach(session.displayCaptions) { caption in
                                Text(caption.text).id(caption.id)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id(bottomAnchor)
                        }
                        .font(.system(size: settings.fontSize, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: min(260, settings.fontSize * 5))
                    .onAppear { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                    .onChange(of: session.displayCaptions) { _, _ in
                        if followsLive { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                    }
                    .onChange(of: followsLive) { _, follow in
                        if follow { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                    }
                    .onChange(of: settings.fontSize) { _, _ in
                        if followsLive { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(.black.opacity(settings.opacity), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 8)
            if settings.position != .bottom { Spacer(minLength: 0) }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
