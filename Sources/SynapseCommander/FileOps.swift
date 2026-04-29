import Foundation
import AppKit

enum ConflictResolution {
    case rename
    case overwrite
    case skip
}

enum FileOps {
    static func copy(_ sources: [URL], to destinationDir: URL) throws {
        for src in sources {
            try copyOne(src, to: destinationDir, resolution: .rename)
        }
    }

    static func move(_ sources: [URL], to destinationDir: URL) throws {
        for src in sources {
            try moveOne(src, to: destinationDir, resolution: .rename)
        }
    }

    /// Copy a single item. Returns the destination URL, or nil if skipped.
    @discardableResult
    static func copyOne(_ src: URL, to destinationDir: URL, resolution: ConflictResolution) throws -> URL? {
        let fm = FileManager.default
        let direct = destinationDir.appendingPathComponent(src.lastPathComponent)
        if fm.fileExists(atPath: direct.path) {
            switch resolution {
            case .skip:
                return nil
            case .overwrite:
                try fm.removeItem(at: direct)
                try fm.copyItem(at: src, to: direct)
                return direct
            case .rename:
                let dst = uniqueDestination(for: src, in: destinationDir)
                try fm.copyItem(at: src, to: dst)
                return dst
            }
        }
        try fm.copyItem(at: src, to: direct)
        return direct
    }

    /// Move a single item. Returns the destination URL, or nil if skipped.
    @discardableResult
    static func moveOne(_ src: URL, to destinationDir: URL, resolution: ConflictResolution) throws -> URL? {
        let fm = FileManager.default
        let direct = destinationDir.appendingPathComponent(src.lastPathComponent)
        if fm.fileExists(atPath: direct.path) {
            switch resolution {
            case .skip:
                return nil
            case .overwrite:
                if direct.standardizedFileURL == src.standardizedFileURL { return direct }
                try fm.removeItem(at: direct)
                try fm.moveItem(at: src, to: direct)
                return direct
            case .rename:
                let dst = uniqueDestination(for: src, in: destinationDir)
                try fm.moveItem(at: src, to: dst)
                return dst
            }
        }
        try fm.moveItem(at: src, to: direct)
        return direct
    }

    static func destinationExists(for src: URL, in destinationDir: URL) -> Bool {
        let direct = destinationDir.appendingPathComponent(src.lastPathComponent)
        return FileManager.default.fileExists(atPath: direct.path)
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
