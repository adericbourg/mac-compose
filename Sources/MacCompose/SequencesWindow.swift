import AppKit
import MacComposeCore
import SwiftUI

/// Lists every loaded compose sequence, with a search field.
@MainActor final class SequencesWindow {
    private var window: NSWindow?

    func show(_ sequences: [[Character]: String], emoji: [EmojiName]) {
        let controller = NSHostingController(rootView: SequencesView(entries: sequenceEntries(sequences) + sequenceEntries(emoji)))
        if let window {
            window.contentViewController = controller
        } else {
            let window = EscClosableWindow(contentViewController: controller)
            window.title = "Compose sequences"
            window.setContentSize(NSSize(width: 640, height: 480))
            window.isReleasedWhenClosed = false
            self.window = window
        }
        // The app is an accessory: without activating it, the window opens behind the front app.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// A plain NSWindow ignores Esc; close on it like a panel does.
private final class EscClosableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

// Not `@State`: its macro plugin ships with Xcode only, and the build uses Command Line Tools.
private final class Search: ObservableObject {
    @Published var query = ""
}

private struct SequencesView: View {
    let entries: [SequenceEntry]
    @StateObject private var search = Search()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading) {
            Table(entries.filter { $0.matches(search.query) }) {
                TableColumn("Keys", value: \.keys)
                TableColumn("Result", value: \.output).width(min: 50, ideal: 60, max: 120)
                TableColumn("Name", value: \.name)
            }
            Text("⎄ is the Compose key, ␣ is Space, ⏎ is Return. Search by result, name or keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .bottom])
        }
        .searchable(text: $search.query, placement: .toolbar, prompt: "Search sequences")
        .searchFocused($isSearchFocused)
        .onAppear { isSearchFocused = true }
    }
}
