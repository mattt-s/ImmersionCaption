import SwiftUI

struct SubtitleView: View {
    @ObservedObject var session: CaptionSession
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack {
            if settings.position != .top { Spacer(minLength: 0) }
            VStack(spacing: 10) {
                Text(session.currentCaption?.text ?? "这里显示应用音频的实时字幕。")
                    .font(.system(size: settings.fontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(6)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.black.opacity(settings.opacity), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 8)
            if settings.position != .bottom { Spacer(minLength: 0) }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
