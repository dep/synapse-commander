import SwiftUI
import AppKit

struct GoToView: View {
    let currentDirectory: URL
    let onGo: (URL) -> Void
    let onDismiss: () -> Void

    @State private var text: String = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go to Folder").font(.headline)
            TextField("~/Downloads, /tmp, ../src", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { submit() }
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else {
                Text("Tab to complete · Enter to go · Esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { onDismiss() }.keyboardShortcut(.cancelAction)
                Button("Go") { submit() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 480)
        .background(
            KeyCatcher(onKey: handleKey).frame(width: 0, height: 0)
        )
        .onAppear { focused = true }
    }

    private func submit() {
        let input = text.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        let resolved = resolvePath(input)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue {
            onGo(resolved)
        } else {
            error = "Not a directory: \(resolved.path)"
        }
    }

    private func resolvePath(_ raw: String) -> URL {
        let expanded = (raw as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return currentDirectory.appendingPathComponent(expanded).standardizedFileURL
    }

    private func complete() {
        let input = text
        // Tab-complete: find the longest unambiguous completion
        // for the last path component.
        let expandedInput = (input as NSString).expandingTildeInPath
        let baseDir: URL
        let prefix: String
        if expandedInput.hasPrefix("/") {
            let u = URL(fileURLWithPath: expandedInput)
            if expandedInput.hasSuffix("/") {
                baseDir = u
                prefix = ""
            } else {
                baseDir = u.deletingLastPathComponent()
                prefix = u.lastPathComponent
            }
        } else {
            let u = currentDirectory.appendingPathComponent(expandedInput)
            if expandedInput.isEmpty || expandedInput.hasSuffix("/") {
                baseDir = u
                prefix = ""
            } else {
                baseDir = u.deletingLastPathComponent()
                prefix = u.lastPathComponent
            }
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }
        let matches = contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            && $0.lastPathComponent.lowercased().hasPrefix(prefix.lowercased())
        }
        guard let first = matches.first else { return }
        if matches.count == 1 {
            // full completion; append trailing slash so next Tab can descend
            text = (input as NSString).deletingLastPathComponent.isEmpty && !input.hasPrefix("/") && !input.hasPrefix("~")
                ? "\(first.lastPathComponent)/"
                : replaceLastComponent(in: input, with: "\(first.lastPathComponent)/")
        } else {
            // longest common prefix among matches
            let names = matches.map { $0.lastPathComponent }
            let common = longestCommonPrefix(of: names)
            if common.count > prefix.count {
                text = replaceLastComponent(in: input, with: common)
            }
        }
    }

    private func replaceLastComponent(in path: String, with comp: String) -> String {
        let ns = path as NSString
        let base = ns.deletingLastPathComponent
        if base.isEmpty { return comp }
        // preserve trailing slash behavior
        return (base as NSString).appendingPathComponent(comp)
    }

    private func longestCommonPrefix(of strings: [String]) -> String {
        guard let first = strings.first else { return "" }
        var prefix = first
        for s in strings.dropFirst() {
            while !s.lowercased().hasPrefix(prefix.lowercased()) {
                prefix = String(prefix.dropLast())
                if prefix.isEmpty { return "" }
            }
        }
        return prefix
    }

    private func handleKey(_ e: KeyEvent) -> Bool {
        if e.keyCode == Keys.escape { onDismiss(); return true }
        if e.keyCode == Keys.tab {
            complete()
            return true
        }
        return false
    }
}
