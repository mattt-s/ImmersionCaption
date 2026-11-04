import SwiftUI

/// Hosted in its own small child panel so locking remains clickable over a pass-through caption.
struct OverlayLockButton: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Button { settings.isOverlayLocked.toggle() } label: {
            Image(systemName: settings.isOverlayLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(settings.opacity), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(settings.isOverlayLocked ? "Unlock and move captions" : "Lock caption position")
        .accessibilityLabel(settings.isOverlayLocked ? "Unlock and move captions" : "Lock caption position")
    }
}
