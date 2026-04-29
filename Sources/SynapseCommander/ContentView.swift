import SwiftUI
import AppKit

enum ActivePane { case left, right }

struct ContentView: View {
    @StateObject private var left = PaneModel(directory: URL(fileURLWithPath: NSHomeDirectory()))
    @StateObject private var right = PaneModel(directory: URL(fileURLWithPath: NSHomeDirectory()))
    @StateObject private var favorites = FavoritesStore()
    @State private var active: ActivePane = .left
    @State private var showFavorites = false
    @State private var showHelp = false
    @State private var showGoTo = false
    @State private var showViewer = false

    // prompt state
    @State private var prompt: PromptKind?
    @State private var promptText: String = ""
    @State private var errorMessage: String?

    // in-progress batch copy/move state (for conflict resolution)
    @State private var pendingBatch: BatchOp?

    // type-ahead state
    @State private var typeAhead: String = ""
    @State private var typeAheadExpires: Date = .distantPast
    private let typeAheadTTL: TimeInterval = 1.0
    private let pageSize: Int = 20

    enum PromptKind: Identifiable {
        case rename(URL)
        case mkdir
        case confirmCopy(sources: [URL], dest: URL)
        case confirmMove(sources: [URL], dest: URL)
        case confirmDelete(sources: [URL])
        case resolveConflict(name: String, isMove: Bool)
        var id: String {
            switch self {
            case .rename(let u): return "rename:\(u.path)"
            case .mkdir: return "mkdir"
            case .confirmCopy: return "copy"
            case .confirmMove: return "move"
            case .confirmDelete: return "delete"
            case .resolveConflict(let n, _): return "conflict:\(n)"
            }
        }
    }

    struct BatchOp {
        enum Kind { case copy, move }
        let kind: Kind
        var remaining: [URL]
        let dest: URL
        var applyToAll: ConflictResolution?
    }

    var activeModel: PaneModel { active == .left ? left : right }
    var otherModel: PaneModel { active == .left ? right : left }

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                PaneView(model: left,
                         isActive: active == .left,
                         onActivate: { active = .left },
                         onOpen: { open($0, in: left) },
                         onDrop: { urls, dest in handleDrop(urls: urls, destination: dest) })
                PaneView(model: right,
                         isActive: active == .right,
                         onActivate: { active = .right },
                         onOpen: { open($0, in: right) },
                         onDrop: { urls, dest in handleDrop(urls: urls, destination: dest) })
            }
            .padding(8)

            KeyCatcher(onKey: handleKey)
                .frame(width: 0, height: 0)

            if showFavorites {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { showFavorites = false }
                FavoritesView(store: favorites,
                              currentDirectory: activeModel.directory,
                              onPick: { fav in
                                  activeModel.navigate(to: fav.url)
                                  showFavorites = false
                              },
                              onDismiss: { showFavorites = false })
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(radius: 20)
            }

            if showHelp {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { showHelp = false }
                HelpView(onDismiss: { showHelp = false })
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(radius: 20)
            }

            if showGoTo {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { showGoTo = false }
                GoToView(currentDirectory: activeModel.directory,
                         onGo: { url in
                             activeModel.navigate(to: url)
                             showGoTo = false
                         },
                         onDismiss: { showGoTo = false })
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(radius: 20)
            }

            if showViewer {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { showViewer = false }
                FileViewerView(model: activeModel,
                               onDismiss: { showViewer = false })
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(radius: 20)
            }

            if !typeAhead.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        if active == .right { Spacer() }
                        Text("⌕ \(typeAhead)")
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.65))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 30)
                        if active == .left { Spacer() }
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .sheet(item: $prompt) { kind in
            promptSheet(for: kind)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Key handling

    private func handleKey(_ e: KeyEvent) -> Bool {
        if prompt != nil || showFavorites || showHelp || showGoTo || showViewer { return false }  // let the sheet handle input

        // "?" opens help (no command/option/control modifiers; shift is fine)
        if e.characters == "?",
           !e.modifiers.contains(.command),
           !e.modifiers.contains(.option),
           !e.modifiers.contains(.control) {
            typeAhead = ""
            showHelp = true
            return true
        }

        // expire stale type-ahead buffer
        if Date() > typeAheadExpires { typeAhead = "" }
        let hasBuffer = !typeAhead.isEmpty

        // Command-modified shortcuts
        if e.modifiers.contains(.command),
           !e.modifiers.contains(.option), !e.modifiers.contains(.control) {
            typeAhead = ""
            switch e.keyCode {
            case Keys.o:
                FileOps.openNatively(activeModel.actionTargets())
                return true
            case Keys.a:
                activeModel.selectAll()
                return true
            case Keys.up:
                activeModel.moveCursorToFirst(); return true
            case Keys.down:
                activeModel.moveCursorToLast(); return true
            case Keys.left:
                sendTargetDir(to: .left); return true
            case Keys.right:
                sendTargetDir(to: .right); return true
            case Keys.delete:
                let srcs = activeModel.actionTargets()
                if !srcs.isEmpty { prompt = .confirmDelete(sources: srcs) }
                return true
            case Keys.g:
                showGoTo = true
                return true
            case Keys.period:
                if e.modifiers.contains(.shift) {
                    let newValue = !left.showHidden
                    left.showHidden = newValue
                    right.showHidden = newValue
                    left.reload(); right.reload()
                    return true
                }
                return false
            default:
                return false
            }
        }

        // Control-modified shortcuts (sort)
        if e.modifiers.contains(.control),
           !e.modifiers.contains(.command), !e.modifiers.contains(.option) {
            typeAhead = ""
            switch e.keyCode {
            case Keys.one:  activeModel.setSort(.name); return true
            case Keys.two:  activeModel.setSort(.size); return true
            case Keys.three: activeModel.setSort(.date); return true
            case Keys.d: showFavorites = true; return true
            case Keys.r: left.reload(); right.reload(); return true
            default: return false
            }
        }

        // Shift-navigation extends selection (no other non-shift modifiers)
        let nonShiftMods = e.modifiers.intersection([.command, .option, .control])
        if nonShiftMods.isEmpty, e.modifiers.contains(.shift) {
            switch e.keyCode {
            case Keys.up:
                typeAhead = ""
                activeModel.moveCursorExtending(delta: -1); return true
            case Keys.down:
                typeAhead = ""
                activeModel.moveCursorExtending(delta: 1); return true
            case Keys.pageUp:
                typeAhead = ""
                activeModel.moveCursorExtending(delta: -pageSize); return true
            case Keys.pageDown:
                typeAhead = ""
                activeModel.moveCursorExtending(delta: pageSize); return true
            case Keys.home:
                typeAhead = ""
                activeModel.moveCursorExtendingToFirst(); return true
            case Keys.end:
                typeAhead = ""
                activeModel.moveCursorExtendingToLast(); return true
            default:
                break
            }
        }

        // modifiers off for the rest (Shift allowed — it's needed for capitals/symbols)
        let mods = e.modifiers.intersection([.command, .option, .control])
        guard mods.isEmpty else { return false }

        switch e.keyCode {
        case Keys.escape:
            if hasBuffer { typeAhead = ""; return true }
            return false
        case Keys.tab:
            typeAhead = ""
            active = (active == .left) ? .right : .left
            return true
        case Keys.space:
            if hasBuffer {
                return appendTypeAhead(" ")
            }
            if let c = activeModel.cursor {
                activeModel.toggleSelect(c)
            }
            return true
        case Keys.up:
            typeAhead = ""; activeModel.clearShiftRange()
            activeModel.moveCursor(delta: -1); return true
        case Keys.down:
            typeAhead = ""; activeModel.clearShiftRange()
            activeModel.moveCursor(delta: 1); return true
        case Keys.home:
            typeAhead = ""; activeModel.clearShiftRange()
            activeModel.moveCursorToFirst(); return true
        case Keys.end:
            typeAhead = ""; activeModel.clearShiftRange()
            activeModel.moveCursorToLast(); return true
        case Keys.pageUp:
            typeAhead = ""; activeModel.clearShiftRange()
            activeModel.moveCursor(delta: -pageSize); return true
        case Keys.pageDown:
            typeAhead = ""; activeModel.clearShiftRange()
            activeModel.moveCursor(delta: pageSize); return true
        case Keys.enter:
            typeAhead = ""
            if let c = activeModel.cursor,
               let entry = activeModel.entries.first(where: { $0.url == c }) {
                open(entry, in: activeModel)
            }
            return true
        case Keys.delete:
            if hasBuffer {
                typeAhead.removeLast()
                typeAheadExpires = Date().addingTimeInterval(typeAheadTTL)
                jumpToTypeAhead()
                return true
            }
            activeModel.goUp(); return true
        case Keys.f2:
            typeAhead = ""
            if let c = activeModel.cursor, !activeModel.isParentRow(c) {
                promptText = c.lastPathComponent
                prompt = .rename(c)
            }
            return true
        case Keys.f3:
            typeAhead = ""
            if let c = activeModel.cursor,
               let entry = activeModel.entries.first(where: { $0.url == c }),
               !entry.isParent, !entry.isDirectory {
                showViewer = true
            }
            return true
        case Keys.f5:
            typeAhead = ""
            let srcs = activeModel.actionTargets()
            if !srcs.isEmpty {
                prompt = .confirmCopy(sources: srcs, dest: otherModel.directory)
            }
            return true
        case Keys.f6:
            typeAhead = ""
            let srcs = activeModel.actionTargets()
            if !srcs.isEmpty {
                prompt = .confirmMove(sources: srcs, dest: otherModel.directory)
            }
            return true
        case Keys.f7:
            typeAhead = ""
            promptText = "New Folder"
            prompt = .mkdir
            return true
        default:
            // type-ahead: single printable character
            if e.characters.count == 1, let ch = e.characters.first, isTypeAheadChar(ch) {
                return appendTypeAhead(String(ch))
            }
            return false
        }
    }

    private func isTypeAheadChar(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber { return true }
        return "._- ()[]{}&+,'~!@#$%^=".contains(c)
    }

    @discardableResult
    private func appendTypeAhead(_ s: String) -> Bool {
        typeAhead += s
        typeAheadExpires = Date().addingTimeInterval(typeAheadTTL)
        jumpToTypeAhead()
        return true
    }

    private func jumpToTypeAhead() {
        let needle = typeAhead.lowercased()
        guard !needle.isEmpty else { return }
        if let match = activeModel.entries.first(where: {
            !$0.isParent && $0.name.lowercased().hasPrefix(needle)
        }) {
            activeModel.cursor = match.url
        }
    }

    // MARK: - Actions

    private func open(_ entry: FileEntry, in pane: PaneModel) {
        if entry.isParent {
            pane.goUp()
        } else if entry.isDirectory {
            let target = (entry.isAlias || entry.isSymlink) ? (entry.resolvedTarget() ?? entry.url) : entry.url
            pane.navigate(to: target)
        } else {
            FileOps.openNatively([entry.url])
        }
    }

    private func performCopy(_ sources: [URL], _ dest: URL) {
        startBatch(BatchOp(kind: .copy, remaining: sources, dest: dest, applyToAll: nil))
    }

    private func performMove(_ sources: [URL], _ dest: URL) {
        startBatch(BatchOp(kind: .move, remaining: sources, dest: dest, applyToAll: nil))
    }

    private func startBatch(_ batch: BatchOp) {
        pendingBatch = batch
        runBatch()
    }

    /// Drains pendingBatch one item at a time. Pauses (without clearing
    /// pendingBatch) when a conflict needs user resolution; resumes via
    /// `resolveConflictAndContinue`.
    private func runBatch() {
        while var batch = pendingBatch, let src = batch.remaining.first {
            let exists = FileOps.destinationExists(for: src, in: batch.dest)
            if exists, batch.applyToAll == nil {
                prompt = .resolveConflict(name: src.lastPathComponent,
                                          isMove: batch.kind == .move)
                return
            }
            batch.remaining.removeFirst()
            pendingBatch = batch
            let resolution: ConflictResolution = exists ? (batch.applyToAll ?? .rename) : .rename
            do {
                switch batch.kind {
                case .copy: try FileOps.copyOne(src, to: batch.dest, resolution: resolution)
                case .move: try FileOps.moveOne(src, to: batch.dest, resolution: resolution)
                }
            } catch {
                errorMessage = error.localizedDescription
                pendingBatch = nil
                left.reload(); right.reload()
                return
            }
        }
        pendingBatch = nil
        left.reload(); right.reload()
        activeModel.selection.removeAll()
    }

    private func resolveConflictAndContinue(_ resolution: ConflictResolution, applyToAll: Bool) {
        guard var batch = pendingBatch, let src = batch.remaining.first else {
            pendingBatch = nil
            return
        }
        if applyToAll { batch.applyToAll = resolution }
        batch.remaining.removeFirst()
        pendingBatch = batch
        do {
            switch batch.kind {
            case .copy: try FileOps.copyOne(src, to: batch.dest, resolution: resolution)
            case .move: try FileOps.moveOne(src, to: batch.dest, resolution: resolution)
            }
        } catch {
            errorMessage = error.localizedDescription
            pendingBatch = nil
            left.reload(); right.reload()
            return
        }
        runBatch()
    }

    private func cancelBatch() {
        pendingBatch = nil
        left.reload(); right.reload()
    }

    private func performRename(_ url: URL, to newName: String) {
        guard !newName.isEmpty, newName != url.lastPathComponent else { return }
        do {
            let newURL = try FileOps.rename(url, to: newName)
            left.reload(); right.reload()
            activeModel.cursor = newURL
        } catch { errorMessage = error.localizedDescription }
    }

    private func performDelete(_ sources: [URL]) {
        do {
            try FileOps.trash(sources)
            left.reload(); right.reload()
            activeModel.selection.removeAll()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Open the cursor/focused directory in the specified pane (left or right).
    /// If the target is a file, opens its parent directory. If parent row, uses its URL.
    private func sendTargetDir(to pane: ActivePane) {
        guard let c = activeModel.cursor,
              let entry = activeModel.entries.first(where: { $0.url == c }) else { return }
        let dir: URL = entry.isDirectory ? entry.url : entry.url.deletingLastPathComponent()
        let destModel = (pane == .left) ? left : right
        destModel.navigate(to: dir)
    }

    /// Handle a drag-and-drop landing on `destination` (a directory URL).
    /// Default action is move; Cmd or Option held during drop = copy
    /// (matches Finder's convention).
    /// Filters out drops where source parent == destination (same-dir no-op)
    /// and drops where source == destination (can't drop a folder into itself).
    private func handleDrop(urls: [URL], destination: URL) {
        let filtered = urls.filter { url in
            url.deletingLastPathComponent().standardizedFileURL.path
                != destination.standardizedFileURL.path
                && url.standardizedFileURL.path != destination.standardizedFileURL.path
        }
        guard !filtered.isEmpty else { return }
        let mods = NSEvent.modifierFlags
        let isCopy = mods.contains(.command) || mods.contains(.option)
        startBatch(BatchOp(kind: isCopy ? .copy : .move,
                           remaining: filtered,
                           dest: destination,
                           applyToAll: nil))
    }

    private func performMkdir(_ name: String) {
        guard !name.isEmpty else { return }
        do {
            let newURL = try FileOps.makeDirectory(in: activeModel.directory, name: name)
            activeModel.reload()
            activeModel.cursor = newURL
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Prompt UI

    @ViewBuilder
    private func promptSheet(for kind: PromptKind) -> some View {
        switch kind {
        case .rename(let url):
            TextPromptView(title: "Rename",
                           message: "Rename \(url.lastPathComponent) to:",
                           text: $promptText,
                           confirmLabel: "Rename") { confirmed in
                if confirmed { performRename(url, to: promptText) }
                prompt = nil
            }
        case .mkdir:
            TextPromptView(title: "New Folder",
                           message: "Create folder in \(activeModel.directory.lastPathComponent):",
                           text: $promptText,
                           confirmLabel: "Create") { confirmed in
                if confirmed { performMkdir(promptText) }
                prompt = nil
            }
        case .confirmCopy(let srcs, let dest):
            ConfirmView(title: "Copy",
                        message: "Copy \(srcs.count) item\(srcs.count == 1 ? "" : "s") to\n\(dest.path)?",
                        confirmLabel: "Copy") { confirmed in
                prompt = nil
                if confirmed {
                    DispatchQueue.main.async { performCopy(srcs, dest) }
                }
            }
        case .confirmMove(let srcs, let dest):
            ConfirmView(title: "Move",
                        message: "Move \(srcs.count) item\(srcs.count == 1 ? "" : "s") to\n\(dest.path)?",
                        confirmLabel: "Move") { confirmed in
                prompt = nil
                if confirmed {
                    DispatchQueue.main.async { performMove(srcs, dest) }
                }
            }
        case .confirmDelete(let srcs):
            let names = srcs.prefix(5).map { $0.lastPathComponent }.joined(separator: "\n")
            let more = srcs.count > 5 ? "\n…and \(srcs.count - 5) more" : ""
            ConfirmView(title: "Move to Trash",
                        message: "Move \(srcs.count) item\(srcs.count == 1 ? "" : "s") to Trash?\n\n\(names)\(more)",
                        confirmLabel: "Delete") { confirmed in
                if confirmed { performDelete(srcs) }
                prompt = nil
            }
        case .resolveConflict(let name, let isMove):
            let remaining = pendingBatch?.remaining.count ?? 0
            ConflictResolveView(name: name,
                                isMove: isMove,
                                showApplyToAll: remaining > 1) { choice in
                prompt = nil
                switch choice {
                case .cancel:
                    cancelBatch()
                case .resolve(let resolution, let all):
                    DispatchQueue.main.async {
                        resolveConflictAndContinue(resolution, applyToAll: all)
                    }
                }
            }
        }
    }
}

private struct TextPromptView: View {
    let title: String
    let message: String
    @Binding var text: String
    let confirmLabel: String
    let done: (Bool) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { done(true) }
            HStack {
                Spacer()
                Button("Cancel") { done(false) }.keyboardShortcut(.cancelAction)
                Button(confirmLabel) { done(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { focused = true }
    }
}

private struct ConfirmView: View {
    let title: String
    let message: String
    let confirmLabel: String
    let done: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { done(false) }.keyboardShortcut(.cancelAction)
                Button(confirmLabel) { done(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

enum ConflictChoice {
    case cancel
    case resolve(ConflictResolution, applyToAll: Bool)
}

private struct ConflictResolveView: View {
    let name: String
    let isMove: Bool
    let showApplyToAll: Bool
    let done: (ConflictChoice) -> Void

    @State private var applyToAll: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Item Already Exists").font(.headline)
            Text("\"\(name)\" already exists at the destination.\nWhat would you like to do?")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if showApplyToAll {
                Toggle("Apply to all remaining conflicts", isOn: $applyToAll)
                    .toggleStyle(.checkbox)
            }
            HStack {
                Button("Cancel") { done(.cancel) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Skip") { done(.resolve(.skip, applyToAll: applyToAll)) }
                Button("Overwrite") { done(.resolve(.overwrite, applyToAll: applyToAll)) }
                Button("Rename") { done(.resolve(.rename, applyToAll: applyToAll)) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
