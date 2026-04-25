import SwiftUI

struct HelpView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Navigation", rows: [
                        ("Tab",              "Switch active pane"),
                        ("↑ / ↓",            "Move cursor"),
                        ("PgUp / PgDn",      "Move cursor by one page"),
                        ("Home / ⌘↑",        "Jump to top"),
                        ("End / ⌘↓",         "Jump to bottom"),
                        ("Enter",            "Open directory or file"),
                        ("Backspace",        "Go up one directory"),
                        ("⌘←",               "Open target directory in left pane"),
                        ("⌘→",               "Open target directory in right pane"),
                        ("⌘G",               "Go to folder by path"),
                    ])
                    section("Selection", rows: [
                        ("Space",            "Toggle selection on cursor row"),
                        ("Shift+↑ / Shift+↓","Extend range selection"),
                        ("Shift+PgUp/PgDn",  "Extend selection by a page"),
                        ("Shift+Home/End",   "Extend selection to top/bottom"),
                        ("⌘A",               "Select all"),
                    ])
                    section("File Operations", rows: [
                        ("F2",               "Rename cursor row"),
                        ("F3",               "Preview file (image/video/audio/text)"),
                        ("F5",               "Copy selection to other pane"),
                        ("F6",               "Move selection to other pane"),
                        ("F7",               "Create new folder"),
                        ("⌘O",               "Open selection with default app"),
                        ("⌘⌫",               "Move selection to Trash"),
                    ])
                    section("Search & Sort", rows: [
                        ("Type letters",     "Type-ahead: jump to first match"),
                        ("Esc",              "Cancel type-ahead"),
                        ("Ctrl+1",           "Sort by name (press again to reverse)"),
                        ("Ctrl+2",           "Sort by size (press again to reverse)"),
                        ("Ctrl+3",           "Sort by date (press again to reverse)"),
                    ])
                    section("Favorites", rows: [
                        ("Ctrl+D",           "Open favorites modal"),
                        ("(in modal) letter/digit", "Jump to favorite by key"),
                        ("(in modal) Esc",   "Close modal"),
                    ])
                    section("Help", rows: [
                        ("?",                "Show this help"),
                        ("Esc",              "Dismiss this help"),
                    ])
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 520, height: 640)
        .background(
            KeyCatcher(onKey: handleKey).frame(width: 0, height: 0)
        )
    }

    private var header: some View {
        HStack {
            Text("Keyboard Shortcuts").font(.headline)
            Spacer()
            Text("press Esc to close")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(r.0)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 180, alignment: .leading)
                    Text(r.1)
                        .font(.system(size: 12))
                    Spacer()
                }
            }
        }
    }

    private func handleKey(_ e: KeyEvent) -> Bool {
        if e.keyCode == Keys.escape { onDismiss(); return true }
        return false
    }
}
