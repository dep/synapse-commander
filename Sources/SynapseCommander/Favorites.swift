import Foundation

struct Favorite: Identifiable, Codable, Hashable {
    var id: UUID
    var key: String      // single character shortcut (lowercased letter or digit)
    var label: String
    var path: String     // absolute filesystem path

    init(id: UUID = UUID(), key: String, label: String, path: String) {
        self.id = id
        self.key = key
        self.label = label
        self.path = path
    }

    var url: URL { URL(fileURLWithPath: path) }
}

@MainActor
final class FavoritesStore: ObservableObject {
    @Published var items: [Favorite] = []

    private let url: URL = {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true)) ?? fm.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("SynapseCommander", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("favorites.json")
    }()

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Favorite].self, from: data)
        else { return }
        items = decoded
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(items) { try? data.write(to: url) }
    }

    func add(path: String, label: String? = nil, preferredKey: String? = nil) -> Favorite {
        let name = label ?? URL(fileURLWithPath: path).lastPathComponent
        let key = preferredKey.flatMap(normalizeKey) ?? nextFreeKey(preferring: name)
        let fav = Favorite(key: key, label: name, path: path)
        items.append(fav)
        save()
        return fav
    }

    func remove(_ fav: Favorite) {
        items.removeAll { $0.id == fav.id }
        save()
    }

    func update(_ fav: Favorite, label: String, key: String) {
        guard let idx = items.firstIndex(where: { $0.id == fav.id }) else { return }
        let normKey = normalizeKey(key) ?? fav.key
        // resolve key conflict by swapping
        if let other = items.firstIndex(where: { $0.key == normKey && $0.id != fav.id }) {
            items[other].key = fav.key
        }
        items[idx].label = label
        items[idx].key = normKey
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func find(byKey key: String) -> Favorite? {
        guard let k = normalizeKey(key) else { return nil }
        return items.first { $0.key == k }
    }

    func exists(path: String) -> Favorite? {
        items.first { $0.path == path }
    }

    private func normalizeKey(_ s: String) -> String? {
        guard let c = s.lowercased().first, c.isLetter || c.isNumber else { return nil }
        return String(c)
    }

    /// Pick a single-char key that isn't in use, preferring the first letter/digit of `hint`.
    private func nextFreeKey(preferring hint: String) -> String {
        let used = Set(items.map { $0.key })
        for c in hint.lowercased() where c.isLetter || c.isNumber {
            let k = String(c)
            if !used.contains(k) { return k }
        }
        for c in "abcdefghijklmnopqrstuvwxyz0123456789" {
            let k = String(c)
            if !used.contains(k) { return k }
        }
        return "?"
    }
}
