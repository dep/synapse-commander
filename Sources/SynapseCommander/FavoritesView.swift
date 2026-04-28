import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FavoritesView: View {
    @ObservedObject var store: FavoritesStore
    let currentDirectory: URL
    let onPick: (Favorite) -> Void
    let onDismiss: () -> Void

    @State private var editing: Favorite?
    @State private var editLabel: String = ""
    @State private var editKey: String = ""
    @State private var hover: UUID?
    @State private var alertMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            if store.items.isEmpty {
                empty
            } else {
                list
            }
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 440, height: 640)
        .background(
            KeyCatcher(onKey: handleKey).frame(width: 0, height: 0)
        )
        .sheet(item: $editing) { fav in
            editSheet(fav)
        }
        .alert("Backup", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("Favorites")
                .font(.headline)
            Spacer()
            Text("press a key to jump")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("No favorites yet")
                .foregroundStyle(.secondary)
            Text(currentDirectory.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.head)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var sortedItems: [Favorite] {
        store.items.sorted { a, b in
            let (ka, kb) = (a.key, b.key)
            let (da, db) = (ka.first?.isNumber ?? false, kb.first?.isNumber ?? false)
            if da != db { return da }  // digits before letters
            return ka < kb
        }
    }

    private var list: some View {
        List {
            ForEach(sortedItems) { fav in
                row(fav)
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ fav: Favorite) -> some View {
        HStack(spacing: 10) {
            Text("[\(fav.key.uppercased())]")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(fav.label).font(.system(size: 13))
                Text(fav.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            if hover == fav.id {
                Button {
                    editLabel = fav.label
                    editKey = fav.key
                    editing = fav
                } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("Rename")

                Button(role: .destructive) {
                    store.remove(fav)
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(hover == fav.id ? Color.white.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { inside in hover = inside ? fav.id : (hover == fav.id ? nil : hover) }
        .onTapGesture { onPick(fav) }
    }

    private var footer: some View {
        HStack {
            if store.exists(path: currentDirectory.path) == nil {
                Button {
                    _ = store.add(path: currentDirectory.path)
                } label: {
                    Label("Add \(currentDirectory.lastPathComponent)", systemImage: "plus")
                }
                .help(currentDirectory.path)
            } else {
                Text("Current folder is already a favorite")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Export…") { exportFavorites() }
                Button("Import…") { importFavorites() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Backup & restore")
            Button("Close") { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Backup

    private func exportFavorites() {
        let panel = NSSavePanel()
        panel.title = "Export Favorites"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "synapse-favorites.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store.exportData()
            try data.write(to: url)
        } catch {
            alertMessage = "Could not export: \(error.localizedDescription)"
        }
    }

    private func importFavorites() {
        let panel = NSOpenPanel()
        panel.title = "Import Favorites"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try store.importData(data)
        } catch {
            alertMessage = "Could not import: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func editSheet(_ fav: Favorite) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Favorite").font(.headline)
            HStack {
                Text("Label").frame(width: 50, alignment: .trailing).foregroundStyle(.secondary)
                TextField("", text: $editLabel).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Key").frame(width: 50, alignment: .trailing).foregroundStyle(.secondary)
                TextField("", text: $editKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onChange(of: editKey) { _, newValue in
                        if newValue.count > 1 { editKey = String(newValue.prefix(1)) }
                    }
                Text("single letter or digit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Spacer()
                Button("Cancel") { editing = nil }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.update(fav, label: editLabel, key: editKey)
                    editing = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    // MARK: - Keys

    private func handleKey(_ e: KeyEvent) -> Bool {
        if editing != nil { return false }
        if e.keyCode == Keys.escape { onDismiss(); return true }
        let mods = e.modifiers.intersection([.command, .option, .control])
        guard mods.isEmpty else { return false }
        if e.characters.count == 1, let ch = e.characters.first,
           ch.isLetter || ch.isNumber {
            if let fav = store.find(byKey: String(ch)) {
                onPick(fav)
                return true
            }
        }
        return false
    }
}
