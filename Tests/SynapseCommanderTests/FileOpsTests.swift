import XCTest
@testable import SynapseCommander

final class FileOpsTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("SynapseCommanderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if fm.fileExists(atPath: tmp.path) {
            try fm.removeItem(at: tmp)
        }
    }

    // MARK: helpers

    private func makeDir(_ name: String, in parent: URL? = nil) throws -> URL {
        let url = (parent ?? tmp).appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ name: String, contents: String = "hello", in parent: URL? = nil) throws -> URL {
        let url = (parent ?? tmp).appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: copy

    func testCopySingleFile() throws {
        let src = try makeDir("src")
        let dst = try makeDir("dst")
        let file = try makeFile("a.txt", in: src)

        try FileOps.copy([file], to: dst)

        XCTAssertTrue(fm.fileExists(atPath: file.path), "source still exists after copy")
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("a.txt").path))
    }

    func testCopyMultipleFiles() throws {
        let src = try makeDir("src")
        let dst = try makeDir("dst")
        let f1 = try makeFile("a.txt", in: src)
        let f2 = try makeFile("b.txt", in: src)

        try FileOps.copy([f1, f2], to: dst)

        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("a.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("b.txt").path))
    }

    func testCopyDirectoryRecursively() throws {
        let src = try makeDir("src")
        let dst = try makeDir("dst")
        let folder = try makeDir("folder", in: src)
        _ = try makeFile("nested.txt", in: folder)

        try FileOps.copy([folder], to: dst)

        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("folder/nested.txt").path))
    }

    func testCopyWithCollisionUsesSuffix() throws {
        let src = try makeDir("src")
        let dst = try makeDir("dst")
        _ = try makeFile("a.txt", contents: "original", in: dst)
        let new = try makeFile("a.txt", contents: "new", in: src)

        try FileOps.copy([new], to: dst)

        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("a.txt"), encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("a 2.txt"), encoding: .utf8), "new")
    }

    func testCopyCollisionPreservesNoExtension() throws {
        let src = try makeDir("src")
        let dst = try makeDir("dst")
        _ = try makeFile("README", contents: "old", in: dst)
        let new = try makeFile("README", contents: "new", in: src)

        try FileOps.copy([new], to: dst)

        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("README 2").path))
    }

    func testCopyMultipleCollisionsIncrement() throws {
        let src = try makeDir("src")
        let dst = try makeDir("dst")
        _ = try makeFile("a.txt", contents: "v1", in: dst)
        _ = try makeFile("a 2.txt", contents: "v2", in: dst)
        let new = try makeFile("a.txt", contents: "v3", in: src)

        try FileOps.copy([new], to: dst)

        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("a 3.txt").path),
                      "should skip past existing 'a 2.txt' to 'a 3.txt'")
    }

    // MARK: move

    func testMoveSingleFile() throws {
        let src = try makeDir("src")
        let dst = try makeDir("dst")
        let file = try makeFile("a.txt", in: src)

        try FileOps.move([file], to: dst)

        XCTAssertFalse(fm.fileExists(atPath: file.path), "source removed after move")
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("a.txt").path))
    }

    func testMoveDirectoryWithContents() throws {
        let src = try makeDir("src")
        let dst = try makeDir("dst")
        let folder = try makeDir("folder", in: src)
        _ = try makeFile("nested.txt", in: folder)

        try FileOps.move([folder], to: dst)

        XCTAssertFalse(fm.fileExists(atPath: folder.path))
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("folder/nested.txt").path))
    }

    func testMoveWithCollisionUsesSuffix() throws {
        let src = try makeDir("src")
        let dst = try makeDir("dst")
        _ = try makeFile("a.txt", contents: "existing", in: dst)
        let new = try makeFile("a.txt", contents: "incoming", in: src)

        try FileOps.move([new], to: dst)

        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("a.txt"), encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("a 2.txt"), encoding: .utf8), "incoming")
        XCTAssertFalse(fm.fileExists(atPath: new.path))
    }

    // MARK: rename

    func testRenameFile() throws {
        let file = try makeFile("old.txt", contents: "hi")
        let renamed = try FileOps.rename(file, to: "new.txt")

        XCTAssertEqual(renamed.lastPathComponent, "new.txt")
        XCTAssertFalse(fm.fileExists(atPath: file.path))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "hi")
    }

    func testRenameToExistingFails() throws {
        _ = try makeFile("a.txt")
        let other = try makeFile("b.txt")
        XCTAssertThrowsError(try FileOps.rename(other, to: "a.txt"),
                             "rename onto existing path should throw")
    }

    // MARK: mkdir

    func testMakeDirectoryCreatesNewFolder() throws {
        let created = try FileOps.makeDirectory(in: tmp, name: "newfolder")
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: created.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testMakeDirectoryFailsIfExists() throws {
        _ = try makeDir("existing")
        XCTAssertThrowsError(try FileOps.makeDirectory(in: tmp, name: "existing"))
    }

    // MARK: trash

    func testTrashRemovesFromOriginalLocation() throws {
        let file = try makeFile("doomed.txt")
        XCTAssertTrue(fm.fileExists(atPath: file.path))

        try FileOps.trash([file])

        XCTAssertFalse(fm.fileExists(atPath: file.path),
                       "file moved to trash, no longer at original path")
    }

    func testTrashMultipleFiles() throws {
        let f1 = try makeFile("a.txt")
        let f2 = try makeFile("b.txt")

        try FileOps.trash([f1, f2])

        XCTAssertFalse(fm.fileExists(atPath: f1.path))
        XCTAssertFalse(fm.fileExists(atPath: f2.path))
    }
}
