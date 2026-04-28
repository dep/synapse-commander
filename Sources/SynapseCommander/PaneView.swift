import SwiftUI
import UniformTypeIdentifiers

struct PaneView: View {
    @ObservedObject var model: PaneModel
    let isActive: Bool
    let onActivate: () -> Void
    let onOpen: (FileEntry) -> Void
    let onDrop: ([URL], URL) -> Void

    @State private var paneDropHover = false
    @State private var rowDropHover: URL?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            list
            Divider().opacity(0.3)
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: paneDropHover ? 2 : (isActive ? 1.5 : 1))
        )
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
        .onDrop(of: [.fileURL], isTargeted: $paneDropHover) { providers in
            handleDropProviders(providers, destination: model.directory)
        }
    }

    private var borderColor: Color {
        if paneDropHover { return Color.green }
        return isActive ? Color.accentColor : Color.white.opacity(0.08)
    }

    /// Decode an array of NSItemProviders carrying file URLs and pass them to the drop callback.
    /// Returns true to accept the drop. Decoding is async so we collect URLs then call back on main.
    private func handleDropProviders(_ providers: [NSItemProvider], destination: URL) -> Bool {
        guard !providers.isEmpty else { return false }
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { item, _ in
                if let url = item as URL? { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            onDrop(urls, destination)
        }
        return true
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(model.directory.path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.secondary)
            Spacer()
            Text(sortLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var sortLabel: String {
        let key: String
        switch model.sortKey {
        case .name: key = "name"
        case .size: key = "size"
        case .date: key = "date"
        }
        return "\(key) \(model.sortAscending ? "↑" : "↓")"
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.entries) { entry in
                        row(entry)
                            .id(entry.url)
                    }
                }
            }
            .onChange(of: model.cursor) { _, newValue in
                if let u = newValue { proxy.scrollTo(u, anchor: nil) }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: FileEntry) -> some View {
        let isCursor = (model.cursor == entry.url) && isActive
        let isSelected = model.selection.contains(entry.url)
        let isDropHover = (rowDropHover == entry.url)

        HStack(spacing: 8) {
            Image(systemName: iconName(for: entry))
                .foregroundStyle(entry.isParent ? Color.secondary
                                                : (entry.isDirectory ? Color.accentColor : Color.secondary))
                .frame(width: 16)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(entry.isParent ? "" : (entry.isDirectory ? "—" : byteString(entry.size)))
                .foregroundStyle(.secondary)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 70, alignment: .trailing)
            Text(entry.isParent ? "" : dateFormatter.string(from: entry.modified))
                .foregroundStyle(.secondary)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .font(.system(size: 12))
        .foregroundStyle(isSelected ? Color.yellow : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(rowBackground(isCursor: isCursor, isDropHover: isDropHover))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        // Single-click fires instantly; double-click runs simultaneously.
        // Stacking .onTapGesture(count: 2) above .onTapGesture(count: 1) makes
        // SwiftUI wait the system double-click interval before firing the
        // single-click — feels laggy. simultaneousGesture sidesteps that.
        .onTapGesture { handleRowClick(entry) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen(entry) })
        .modifier(RowDragModifier(entry: entry, model: model))
        .modifier(RowDropModifier(entry: entry,
                                  rowDropHover: $rowDropHover,
                                  onDropProviders: handleDropProviders))
    }

    private func rowBackground(isCursor: Bool, isDropHover: Bool) -> Color {
        if isDropHover { return Color.green.opacity(0.35) }
        if isCursor { return Color.accentColor.opacity(0.25) }
        return Color.clear
    }

    /// Handle a single (non-double) row click. Reads modifier flags directly from
    /// NSEvent since SwiftUI's .onTapGesture doesn't expose them.
    /// - plain click: move cursor (clears any selection-via-shift state)
    /// - shift-click: select inclusive range from anchor (or cursor) to clicked row
    /// - cmd-click: toggle individual row selection
    private func handleRowClick(_ entry: FileEntry) {
        onActivate()
        let mods = NSEvent.modifierFlags
        let shift = mods.contains(.shift)
        let cmd = mods.contains(.command)

        if shift && !entry.isParent {
            let anchor = model.shiftAnchor ?? model.cursor ?? entry.url
            model.shiftAnchor = anchor
            model.selectRange(from: anchor, to: entry.url)
            model.cursor = entry.url
        } else if cmd && !entry.isParent {
            model.toggleSelect(entry.url)
            model.cursor = entry.url
            model.shiftAnchor = entry.url
        } else {
            model.shiftAnchor = entry.url
            model.cursor = entry.url
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(model.entries.filter { !$0.isParent }.count) items")
            if !model.selection.isEmpty {
                Text("·")
                Text("\(model.selection.count) selected")
                    .foregroundStyle(Color.yellow)
            }
            Spacer()
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private func iconName(for entry: FileEntry) -> String {
        if entry.isParent { return "arrow.turn.left.up" }
        if entry.isAlias || entry.isSymlink {
            return entry.isDirectory ? "folder.fill.badge.questionmark" : "arrowshape.turn.up.right"
        }
        if entry.isDirectory { return "folder.fill" }
        return Self.iconForExtension(entry.url.pathExtension.lowercased())
    }

    private static let extensionIcons: [String: String] = [
        // Images
        "png": "photo", "jpg": "photo", "jpeg": "photo", "gif": "photo",
        "bmp": "photo", "tiff": "photo", "tif": "photo", "webp": "photo",
        "heic": "photo", "heif": "photo", "svg": "photo", "ico": "photo",
        "raw": "photo", "cr2": "photo", "nef": "photo", "arw": "photo",
        // Video
        "mp4": "film", "mov": "film", "avi": "film", "mkv": "film",
        "wmv": "film", "flv": "film", "webm": "film", "m4v": "film",
        "mpg": "film", "mpeg": "film",
        // Audio
        "mp3": "music.note", "wav": "music.note", "flac": "music.note",
        "aac": "music.note", "ogg": "music.note", "m4a": "music.note",
        "wma": "music.note", "aiff": "music.note", "opus": "music.note",
        // Archives
        "zip": "doc.zipper", "tar": "doc.zipper", "gz": "doc.zipper",
        "tgz": "doc.zipper", "bz2": "doc.zipper", "xz": "doc.zipper",
        "7z": "doc.zipper", "rar": "doc.zipper", "dmg": "doc.zipper",
        "iso": "doc.zipper", "pkg": "doc.zipper",
        // Documents
        "pdf": "doc.richtext",
        "doc": "doc.text", "docx": "doc.text", "rtf": "doc.text",
        "odt": "doc.text", "pages": "doc.text",
        "txt": "doc.plaintext", "md": "doc.plaintext", "markdown": "doc.plaintext",
        "log": "doc.plaintext", "rst": "doc.plaintext",
        // Spreadsheets
        "xls": "tablecells", "xlsx": "tablecells", "csv": "tablecells",
        "tsv": "tablecells", "ods": "tablecells", "numbers": "tablecells",
        // Presentations
        "ppt": "rectangle.on.rectangle", "pptx": "rectangle.on.rectangle",
        "odp": "rectangle.on.rectangle", "key": "rectangle.on.rectangle",
        // Code
        "swift": "chevron.left.forwardslash.chevron.right",
        "js": "chevron.left.forwardslash.chevron.right",
        "jsx": "chevron.left.forwardslash.chevron.right",
        "ts": "chevron.left.forwardslash.chevron.right",
        "tsx": "chevron.left.forwardslash.chevron.right",
        "py": "chevron.left.forwardslash.chevron.right",
        "rb": "chevron.left.forwardslash.chevron.right",
        "go": "chevron.left.forwardslash.chevron.right",
        "rs": "chevron.left.forwardslash.chevron.right",
        "java": "chevron.left.forwardslash.chevron.right",
        "kt": "chevron.left.forwardslash.chevron.right",
        "c": "chevron.left.forwardslash.chevron.right",
        "h": "chevron.left.forwardslash.chevron.right",
        "cpp": "chevron.left.forwardslash.chevron.right",
        "hpp": "chevron.left.forwardslash.chevron.right",
        "cs": "chevron.left.forwardslash.chevron.right",
        "php": "chevron.left.forwardslash.chevron.right",
        "lua": "chevron.left.forwardslash.chevron.right",
        "sh": "chevron.left.forwardslash.chevron.right",
        "bash": "chevron.left.forwardslash.chevron.right",
        "zsh": "chevron.left.forwardslash.chevron.right",
        "fish": "chevron.left.forwardslash.chevron.right",
        "sql": "chevron.left.forwardslash.chevron.right",
        // Markup / data
        "html": "curlybraces", "htm": "curlybraces", "xml": "curlybraces",
        "json": "curlybraces", "yaml": "curlybraces", "yml": "curlybraces",
        "toml": "curlybraces", "plist": "curlybraces",
        "css": "paintpalette", "scss": "paintpalette", "sass": "paintpalette",
        "less": "paintpalette",
        // Fonts
        "ttf": "textformat", "otf": "textformat", "woff": "textformat",
        "woff2": "textformat", "eot": "textformat",
        // Executables / binaries
        "app": "app.badge", "exe": "terminal", "bin": "terminal",
        "out": "terminal", "dll": "terminal", "so": "terminal", "dylib": "terminal",
        // Disk/system
        "sqlite": "cylinder", "db": "cylinder",
        // Config
        "env": "gearshape", "ini": "gearshape", "conf": "gearshape", "cfg": "gearshape",
        // Design
        "psd": "paintbrush", "ai": "paintbrush", "sketch": "paintbrush",
        "fig": "paintbrush", "xd": "paintbrush",
        // E-books
        "epub": "book", "mobi": "book", "azw": "book", "azw3": "book"
    ]

    private static func iconForExtension(_ ext: String) -> String {
        if ext.isEmpty { return "doc" }
        return extensionIcons[ext] ?? "doc"
    }
}

/// Attaches a custom AppKit drag source to a row. Unlike SwiftUI's .onDrag,
/// this lets us advertise the correct NSDragOperation (move by default,
/// copy when Cmd or Option is held) so the system shows the right cursor —
/// no spurious green "+" plus during a move.
/// Bundles the entire selection if the dragged row is part of it.
/// Skips parent (..) row.
private struct RowDragModifier: ViewModifier {
    let entry: FileEntry
    @ObservedObject var model: PaneModel

    func body(content: Content) -> some View {
        if entry.isParent {
            content
        } else {
            content.overlay(
                DragSourceView(urlsProvider: { urlsToDrag() })
            )
        }
    }

    private func urlsToDrag() -> [URL] {
        if model.selection.contains(entry.url) && model.selection.count > 1 {
            return Array(model.selection)
        }
        return [entry.url]
    }
}

/// Transparent NSView overlay that initiates an AppKit drag with explicit
/// source operations. Reports `.move` by default, `.copy` when Cmd or Option
/// is held — which drives the system cursor (no "+" badge during move).
///
/// The overlay declines hit-testing (returns nil) so SwiftUI receives all
/// clicks normally. It uses a window-level mouse-event monitor to detect when
/// a drag begins inside its bounds, then takes over for the drag session.
private struct DragSourceView: NSViewRepresentable {
    let urlsProvider: () -> [URL]

    func makeNSView(context: Context) -> NSView {
        let v = DragSourceNSView()
        v.urlsProvider = urlsProvider
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragSourceNSView)?.urlsProvider = urlsProvider
    }

    final class DragSourceNSView: NSView, NSDraggingSource {
        var urlsProvider: (() -> [URL])?
        private var mouseDownMonitor: Any?
        private var mouseDraggedMonitor: Any?
        private var lastMouseDown: NSEvent?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }
        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        // Click-through: never claim a hit. SwiftUI handles all taps.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitors()
            guard window != nil else { return }

            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self = self else { return event }
                if self.eventIsInBounds(event) {
                    self.lastMouseDown = event
                } else {
                    self.lastMouseDown = nil
                }
                return event
            }
            mouseDraggedMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                guard let self = self,
                      let down = self.lastMouseDown,
                      self.eventIsInBounds(down),
                      let urls = self.urlsProvider?(), !urls.isEmpty
                else { return event }
                // Require the cursor to travel a few pixels before starting a drag.
                // Without this threshold, any sub-pixel jitter during a click triggers
                // the drag session and interferes with simple selection clicks.
                let dx = event.locationInWindow.x - down.locationInWindow.x
                let dy = event.locationInWindow.y - down.locationInWindow.y
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance >= 4 else { return event }
                // Only start once per gesture.
                self.lastMouseDown = nil
                self.startDrag(urls: urls, mouseDown: down)
                return event
            }
        }

        override func removeFromSuperview() {
            removeMonitors()
            super.removeFromSuperview()
        }

        private func removeMonitors() {
            if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
            if let m = mouseDraggedMonitor { NSEvent.removeMonitor(m); mouseDraggedMonitor = nil }
        }

        private func eventIsInBounds(_ event: NSEvent) -> Bool {
            guard let window = window, event.window === window else { return false }
            let pt = self.convert(event.locationInWindow, from: nil)
            return self.bounds.contains(pt)
        }

        private func startDrag(urls: [URL], mouseDown: NSEvent) {
            let items: [NSDraggingItem] = urls.map { url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let pt = self.convert(mouseDown.locationInWindow, from: nil)
                item.draggingFrame = NSRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)
                return item
            }
            beginDraggingSession(with: items, event: mouseDown, source: self)
        }

        // MARK: NSDraggingSource

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            switch context {
            case .outsideApplication:
                return [.copy]
            case .withinApplication:
                let mods = NSEvent.modifierFlags
                if mods.contains(.command) || mods.contains(.option) {
                    return [.copy]
                }
                return [.move]
            @unknown default:
                return [.move]
            }
        }
    }
}

/// Adds .onDrop to directory rows so users can drop directly into a folder
/// instead of the pane's current directory. Non-directories pass through.
private struct RowDropModifier: ViewModifier {
    let entry: FileEntry
    @Binding var rowDropHover: URL?
    let onDropProviders: ([NSItemProvider], URL) -> Bool

    func body(content: Content) -> some View {
        if entry.isDirectory && !entry.isParent {
            content.onDrop(of: [.fileURL],
                           isTargeted: Binding(
                               get: { rowDropHover == entry.url },
                               set: { rowDropHover = $0 ? entry.url : nil })) { providers in
                onDropProviders(providers, entry.url)
            }
        } else {
            content
        }
    }
}
