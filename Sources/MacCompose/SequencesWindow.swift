import AppKit
import MacComposeCore
import SwiftUI

/// Lists every loaded compose sequence, with a search field.
@MainActor final class SequencesWindow {
    private var window: NSWindow?

    func show(_ sequences: [[Character]: String]) {
        let controller = NSHostingController(rootView: SequencesView(entries: sequenceEntries(sequences)))
        if let window {
            window.contentViewController = controller
        } else {
            let window = NSWindow(contentViewController: controller)
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

// Not `@State`: its macro plugin ships with Xcode only, and the build uses Command Line Tools.
private final class Search: ObservableObject {
    @Published var query = ""
}

private struct SequencesView: View {
    let entries: [SequenceEntry]
    @StateObject private var search = Search()

    var body: some View {
        VStack(alignment: .leading) {
            Table(entries.filter { $0.matches(search.query) }) {
                TableColumn("Keys", value: \.keys)
                TableColumn("Result", value: \.output).width(min: 50, ideal: 60, max: 120)
                TableColumn("Name", value: \.name)
            }
            Text("⎄ is the Compose key, ␣ is Space. Search by result, name or keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .bottom])
        }
        .searchable(text: $search.query, placement: .toolbar, prompt: "Search sequences")
    }
}
