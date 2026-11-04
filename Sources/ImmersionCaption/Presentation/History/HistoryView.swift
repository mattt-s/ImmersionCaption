import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CaptionCore

struct HistoryView: View {
    @ObservedObject var session: CaptionSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Subtitle history").font(.headline)
                Spacer()
                Button("Export…") { exportHistory() }.disabled(session.history.isEmpty)
                Button("Clear") { session.clearHistory() }.disabled(session.history.isEmpty)
            }
            Text("Up to 300 recognition blocks. Live text is revised in place; history stays in memory.").font(.caption).foregroundStyle(.secondary)
            if session.history.isEmpty {
                Text("Recognized captions will appear here.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                List(session.history.reversed()) { caption in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(caption.text).font(.body)
                        if !caption.languageIdentifier.isEmpty {
                            Text(Locale.current.localizedString(forIdentifier: caption.languageIdentifier)
                                 ?? caption.languageIdentifier).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(caption.createdAt, style: .time).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .textSelection(.enabled)
                }.listStyle(.inset)
            }
        }
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ImmersionCaption-history.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = session.history.map(\.text).joined(separator: "\n\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
