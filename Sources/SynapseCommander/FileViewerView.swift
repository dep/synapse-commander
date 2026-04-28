import SwiftUI
import AppKit
import AVKit

struct FileViewerView: View {
    @ObservedObject var model: PaneModel
    let onDismiss: () -> Void

    private static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp",
        "heic", "heif", "ico", "raw", "cr2", "nef", "arw"
    ]
    private static let videoExts: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg"
    ]
    private static let audioExts: Set<String> = [
        "mp3", "wav", "flac", "aac", "ogg", "m4a", "wma", "aiff", "opus"
    ]
    // Hard cap so we never freeze the UI loading a 500MB log file.
    private static let textByteLimit = 2 * 1024 * 1024

    private var currentURL: URL? {
        guard let c = model.cursor,
              let entry = model.entries.first(where: { $0.url == c }),
              !entry.isParent, !entry.isDirectory
        else { return nil }
        return entry.url
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 900, height: 640)
        .background(
            KeyCatcher(onKey: handleKey).frame(width: 0, height: 0)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .foregroundStyle(.secondary)
            Text(currentURL?.lastPathComponent ?? "No file")
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("press Esc to close · ↑/↓ next file")
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

    @ViewBuilder
    private var content: some View {
        if let url = currentURL {
            viewer(for: url)
                .id(url)  // recreate subviews when cursor moves to a new file
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.25))
        } else {
            unsupported(message: "Nothing to preview.")
        }
    }

    @ViewBuilder
    private func viewer(for url: URL) -> some View {
        let ext = url.pathExtension.lowercased()
        if Self.imageExts.contains(ext) {
            imageViewer(url)
        } else if Self.videoExts.contains(ext) {
            MediaPlayerView(url: url, controlsStyle: .floating)
        } else if Self.audioExts.contains(ext) {
            audioViewer(url)
        } else {
            textOrUnsupported(url)
        }
    }

    @ViewBuilder
    private func imageViewer(_ url: URL) -> some View {
        if let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.medium)
                .scaledToFit()
                .padding(8)
        } else {
            unsupported(message: "Could not decode image.")
        }
    }

    @ViewBuilder
    private func audioViewer(_ url: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            MediaPlayerView(url: url, controlsStyle: .inline)
                .frame(height: 60)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func textOrUnsupported(_ url: URL) -> some View {
        if let text = loadText(url) {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            unsupported(message: "Cannot preview this file type.")
        }
    }

    private func loadText(_ url: URL) -> String? {
        // Only attempt if file is small enough; reject obvious binaries.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size <= Self.textByteLimit
        else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Heuristic: if there's a NUL in the first 4KB, treat as binary.
        let probe = data.prefix(4096)
        if probe.contains(0) { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private func unsupported(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleKey(_ e: KeyEvent) -> Bool {
        switch e.keyCode {
        case Keys.escape:
            onDismiss(); return true
        case Keys.up:
            moveToAdjacentFile(delta: -1); return true
        case Keys.down:
            moveToAdjacentFile(delta: 1); return true
        default:
            return false
        }
    }

    /// Move the pane cursor to the previous/next non-directory, non-parent entry.
    /// If none exists in that direction, leave cursor where it is.
    private func moveToAdjacentFile(delta: Int) {
        guard let c = model.cursor,
              let idx = model.entries.firstIndex(where: { $0.url == c })
        else { return }
        let stride = delta > 0 ? 1 : -1
        var i = idx + stride
        while i >= 0 && i < model.entries.count {
            let entry = model.entries[i]
            if !entry.isParent && !entry.isDirectory {
                model.cursor = entry.url
                return
            }
            i += stride
        }
    }
}

/// AppKit-backed media player. We use AVPlayerView directly instead of SwiftUI's
/// VideoPlayer because the latter crashes on macOS when fed audio-only sources
/// ("failed to demangle superclass of VideoPlayerView").
private struct MediaPlayerView: NSViewRepresentable {
    enum Controls { case floating, inline }
    let url: URL
    let controlsStyle: Controls

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = (controlsStyle == .floating) ? .floating : .inline
        v.player = AVPlayer(url: url)
        v.showsFullScreenToggleButton = false
        v.player?.play()
        return v
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // If the URL changed (e.g. user hit ↑/↓ to move to next file), swap the player.
        if (nsView.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            nsView.player?.pause()
            nsView.player = AVPlayer(url: url)
            nsView.player?.play()
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}
