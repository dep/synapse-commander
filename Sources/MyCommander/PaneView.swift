import SwiftUI

struct PaneView: View {
    @ObservedObject var model: PaneModel
    let isActive: Bool
    let onActivate: () -> Void
    let onOpen: (FileEntry) -> Void

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
                .stroke(isActive ? Color.accentColor : Color.white.opacity(0.08),
                        lineWidth: isActive ? 1.5 : 1)
        )
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
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
                if let u = newValue { withAnimation(.linear(duration: 0.05)) { proxy.scrollTo(u, anchor: .center) } }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: FileEntry) -> some View {
        let isCursor = (model.cursor == entry.url) && isActive
        let isSelected = model.selection.contains(entry.url)

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
                .fill(isCursor ? Color.accentColor.opacity(0.25) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(entry) }
        .onTapGesture { onActivate(); model.cursor = entry.url }
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
