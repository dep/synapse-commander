import Foundation
import AppKit

enum FileOps {
    static func copy(_ sources: [URL], to destinationDir: URL) throws {
        let fm = FileManager.default
        for src in sources {
            let dst = uniqueDestination(for: src, in: destinationDir)
            try fm.copyItem(at: src, to: dst)
        }
    }

    static func move(_ sources: [URL], to destinationDir: URL) throws {
        let fm = FileManager.default
        for src in sources {
            let dst = uniqueDestination(for: src, in: destinationDir)
            try fm.moveItem(at: src, to: dst)
        }
    }

    static func rename(_ url: URL, to newName: String) throws -> URL {
        let dst = url.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: url, to: dst)
        return dst
    }

    static func makeDirectory(in parent: URL, name: String) throws -> URL {
        let dst = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: false)
        return dst
    }

    static func openNatively(_ urls: [URL]) {
        for url in urls { NSWorkspace.shared.open(url) }
    }

    static func trash(_ urls: [URL]) throws {
        let fm = FileManager.default
        for url in urls {
            try fm.trashItem(at: url, resultingItemURL: nil)
        }
    }

    private static func uniqueDestination(for src: URL, in dir: URL) -> URL {
        let fm = FileManager.default
        let base = src.deletingPathExtension().lastPathComponent
        let ext = src.pathExtension
        var candidate = dir.appendingPathComponent(src.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            n += 1
        }
        return candidate
    }
}
