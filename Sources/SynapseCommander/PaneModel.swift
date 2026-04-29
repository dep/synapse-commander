import Foundation
import AppKit

struct FileEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let modified: Date
    var isParent: Bool = false
    var isAlias: Bool = false       // Finder alias (resolves via bookmark data)
    var isSymlink: Bool = false     // POSIX symlink

    var id: URL { url }
    var name: String { isParent ? ".." : url.lastPathComponent }

    /// The target to navigate to when this entry is opened as a directory.
    /// Resolves Finder aliases; symlinks are resolved by Foundation automatically.
    func resolvedTarget() -> URL? {
        if isAlias {
            return try? URL(resolvingAliasFileAt: url, options: [])
        }
        return url.resolvingSymlinksInPath()
    }
}

enum SortKey { case name, size, date }

@MainActor
final class PaneModel: ObservableObject {
    @Published var directory: URL
    @Published var entries: [FileEntry] = []
    @Published var selection: Set<URL> = []     // checked with space
    @Published var cursor: URL?                  // focused row
    @Published var sortKey: SortKey = .name
    @Published var sortAscending: Bool = true
    @Published var showHidden: Bool = false
    /// Anchor URL for shift-selection. nil until a shift-arrow press starts a range.
    var shiftAnchor: URL?
    /// Selection snapshot taken when a new shift-arrow range begins. The active
    /// shift range is unioned with this so previously-selected ranges survive.
    var shiftSelectionBase: Set<URL> = []

    /// Drop the active shift-range. Call when an unmodified arrow / Home / End
    /// signals the user has ended the current range.
    func clearShiftRange() {
        shiftAnchor = nil
        shiftSelectionBase = []
    }

    init(directory: URL) {
        self.directory = directory
        reload()
    }

    func setSort(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
        reload()
    }

    func reload() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            .isAliasFileKey, .isSymbolicLinkKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        let contents = (try? fm.contentsOfDirectory(at: directory,
                                                    includingPropertiesForKeys: keys,
                                                    options: options)) ?? []
        var result: [FileEntry] = []
        for url in contents {
            let vals = try? url.resourceValues(forKeys: Set(keys))
            let isAlias = vals?.isAliasFile ?? false
            let isSymlink = vals?.isSymbolicLink ?? false
            var isDir = vals?.isDirectory ?? false

            // Aliases and symlinks report as non-directories at this level.
            // Probe the resolved target so we can display them as folders.
            if !isDir, isAlias, let t = try? URL(resolvingAliasFileAt: url, options: []),
               (try? t.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                isDir = true
            } else if !isDir, isSymlink {
                let t = url.resolvingSymlinksInPath()
                if (try? t.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    isDir = true
                }
            }

            result.append(FileEntry(
                url: url,
                isDirectory: isDir,
                size: Int64(vals?.fileSize ?? 0),
                modified: vals?.contentModificationDate ?? .distantPast,
                isAlias: isAlias,
                isSymlink: isSymlink
            ))
        }
        result.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            let ordered: Bool
            switch sortKey {
            case .name:
                ordered = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .size:
                if a.size == b.size {
                    ordered = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                } else {
                    ordered = a.size < b.size
                }
            case .date:
                if a.modified == b.modified {
                    ordered = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                } else {
                    ordered = a.modified < b.modified
                }
            }
            return sortAscending ? ordered : !ordered
        }
        let parent = directory.deletingLastPathComponent()
        if parent.path != directory.path {
            result.insert(FileEntry(url: parent, isDirectory: true, size: 0,
                                    modified: .distantPast, isParent: true),
                          at: 0)
        }
        entries = result
        selection = selection.intersection(Set(result.map { $0.url }))
        if let cur = cursor, !entries.contains(where: { $0.url == cur }) {
            cursor = entries.first?.url
        } else if cursor == nil {
            cursor = entries.first?.url
        }
    }

    func navigate(to url: URL) {
        directory = url
        selection.removeAll()
        cursor = nil
        clearShiftRange()
        reload()
    }

    func goUp() {
        let parent = directory.deletingLastPathComponent()
        if parent.path != directory.path {
            let previous = directory
            navigate(to: parent)
            // place cursor on the directory we came from
            if entries.contains(where: { $0.url == previous }) { cursor = previous }
        }
    }

    func toggleSelect(_ url: URL) {
        if isParentRow(url) { return }
        if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
    }

    /// Targets for an action: selected items, or the cursor row if none selected.
    func actionTargets() -> [URL] {
        if !selection.isEmpty { return Array(selection) }
        if let c = cursor, !isParentRow(c) { return [c] }
        return []
    }

    func isParentRow(_ url: URL) -> Bool {
        entries.first(where: { $0.url == url })?.isParent == true
    }

    func moveCursor(delta: Int) {
        guard !entries.isEmpty else { return }
        let idx = entries.firstIndex(where: { $0.url == cursor }) ?? -1
        let next = max(0, min(entries.count - 1, idx + delta))
        cursor = entries[next].url
    }

    /// Moves cursor by delta and extends the selection from the shift anchor
    /// to the new cursor position. Parent ".." row is never selected.
    func moveCursorExtending(delta: Int) {
        guard !entries.isEmpty else { return }
        beginShiftRangeIfNeeded()
        moveCursor(delta: delta)
        applyShiftSelection()
    }

    func moveCursorExtendingToFirst() {
        guard !entries.isEmpty else { return }
        beginShiftRangeIfNeeded()
        moveCursorToFirst()
        applyShiftSelection()
    }

    func moveCursorExtendingToLast() {
        guard !entries.isEmpty else { return }
        beginShiftRangeIfNeeded()
        moveCursorToLast()
        applyShiftSelection()
    }

    /// Start a fresh shift-range from the current cursor, preserving the
    /// existing selection as the base so subsequent shift-arrows append.
    private func beginShiftRangeIfNeeded() {
        if shiftAnchor == nil {
            shiftAnchor = cursor
            shiftSelectionBase = selection
        }
    }

    private func applyShiftSelection() {
        guard let anchor = shiftAnchor, let cur = cursor,
              let aIdx = entries.firstIndex(where: { $0.url == anchor }),
              let cIdx = entries.firstIndex(where: { $0.url == cur })
        else { return }
        let (lo, hi) = aIdx <= cIdx ? (aIdx, cIdx) : (cIdx, aIdx)
        let range = entries[lo...hi].filter { !$0.isParent }.map { $0.url }
        selection = shiftSelectionBase.union(range)
    }

    func moveCursorToFirst() {
        cursor = entries.first(where: { !$0.isParent })?.url ?? entries.first?.url
    }

    func moveCursorToLast() {
        cursor = entries.last?.url
    }

    func selectAll() {
        selection = Set(entries.filter { !$0.isParent }.map { $0.url })
    }

    /// Replace selection with the inclusive range of rows between `anchor` and `target`.
    /// Used for shift-click. Skips parent row.
    func selectRange(from anchor: URL, to target: URL) {
        guard let aIdx = entries.firstIndex(where: { $0.url == anchor }),
              let tIdx = entries.firstIndex(where: { $0.url == target })
        else { return }
        let (lo, hi) = aIdx <= tIdx ? (aIdx, tIdx) : (tIdx, aIdx)
        selection = Set(entries[lo...hi].filter { !$0.isParent }.map { $0.url })
    }
}
