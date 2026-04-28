import XCTest
@testable import SynapseCommander

@MainActor
final class PaneModelTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        let raw = fm.temporaryDirectory.appendingPathComponent("PaneModelTests-\(UUID().uuidString)")
        try fm.createDirectory(at: raw, withIntermediateDirectories: true)
        // FileManager.contentsOfDirectory returns URLs with /private/var symlink resolved
        // and trailing slashes on directories — match that so URL equality works.
        tmp = raw.resolvingSymlinksInPath()
    }

    override func tearDown() async throws {
        if fm.fileExists(atPath: tmp.path) {
            try fm.removeItem(at: tmp)
        }
    }

    // MARK: helpers

    private func makeFile(_ name: String, contents: String = "x", in parent: URL? = nil) throws -> URL {
        let url = (parent ?? tmp).appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeDir(_ name: String, in parent: URL? = nil) throws -> URL {
        let url = (parent ?? tmp).appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Standard fixture: a directory with file1.txt, file2.txt, file3.txt and a subfolder.
    /// Returns the model and URLs derived from `model.entries` (skipping the parent row),
    /// since FileManager normalizes URLs differently from raw construction
    /// (resolves /private symlink, adds trailing slash to directories).
    private func seedStandardFixture() throws -> (model: PaneModel, items: [URL]) {
        _ = try makeFile("file1.txt")
        _ = try makeFile("file2.txt")
        _ = try makeFile("file3.txt")
        _ = try makeDir("subfolder")
        let model = PaneModel(directory: tmp)
        let items = model.entries.filter { !$0.isParent }.map { $0.url }
        // Expected order: subfolder, file1.txt, file2.txt, file3.txt
        return (model, items)
    }

    // MARK: reload + sort

    func testReloadIncludesParentRowWhenNotAtRoot() throws {
        _ = try makeFile("a.txt")
        let model = PaneModel(directory: tmp)
        XCTAssertTrue(model.entries.first?.isParent == true,
                      "first entry should be the parent (..) row")
    }

    func testEntriesSortDirectoriesBeforeFiles() throws {
        _ = try makeFile("a.txt")
        _ = try makeDir("zzz")  // alphabetically last but a directory
        let model = PaneModel(directory: tmp)
        let nonParent = model.entries.filter { !$0.isParent }
        XCTAssertEqual(nonParent.first?.name, "zzz", "directories sort before files")
    }

    func testSortByNameAscendingThenDescending() throws {
        _ = try makeFile("apple.txt")
        _ = try makeFile("banana.txt")
        _ = try makeFile("cherry.txt")
        let model = PaneModel(directory: tmp)

        let asc = model.entries.filter { !$0.isParent }.map { $0.name }
        XCTAssertEqual(asc, ["apple.txt", "banana.txt", "cherry.txt"])

        // Toggle to descending by setting same key again
        model.setSort(.name)
        let desc = model.entries.filter { !$0.isParent }.map { $0.name }
        XCTAssertEqual(desc, ["cherry.txt", "banana.txt", "apple.txt"])
    }

    func testSortBySizeUsesNameAsTieBreaker() throws {
        _ = try makeFile("a.txt", contents: "xxx")  // 3 bytes
        _ = try makeFile("b.txt", contents: "x")    // 1 byte
        _ = try makeFile("c.txt", contents: "x")    // 1 byte (tie with b)
        let model = PaneModel(directory: tmp)
        model.setSort(.size)

        let names = model.entries.filter { !$0.isParent }.map { $0.name }
        XCTAssertEqual(names, ["b.txt", "c.txt", "a.txt"],
                       "size asc with name tie-break: 1B (b before c), then 3B")
    }

    // MARK: cursor movement

    func testMoveCursorWithinBounds() throws {
        let (model, items) = try seedStandardFixture()
        // Cursor starts at entries.first which is the parent ".." row.
        XCTAssertEqual(model.cursor, model.entries.first?.url)

        model.moveCursor(delta: 1)
        XCTAssertEqual(model.cursor, items[0])  // subfolder
        model.moveCursor(delta: 1)
        XCTAssertEqual(model.cursor, items[1])  // file1.txt
    }

    func testMoveCursorClampsAtFirst() throws {
        let (model, _) = try seedStandardFixture()
        model.moveCursor(delta: -100)
        XCTAssertEqual(model.cursor, model.entries.first?.url)
    }

    func testMoveCursorClampsAtLast() throws {
        let (model, _) = try seedStandardFixture()
        model.moveCursor(delta: 100)
        XCTAssertEqual(model.cursor, model.entries.last?.url)
    }

    func testMoveCursorToFirstSkipsParent() throws {
        let (model, items) = try seedStandardFixture()
        model.moveCursorToFirst()
        XCTAssertEqual(model.cursor, items[0],
                       "moveCursorToFirst should skip the parent row")
    }

    func testMoveCursorToLast() throws {
        let (model, items) = try seedStandardFixture()
        model.moveCursorToLast()
        XCTAssertEqual(model.cursor, items[3])
    }

    // MARK: selection

    func testToggleSelect() throws {
        let (model, items) = try seedStandardFixture()
        model.toggleSelect(items[1])
        XCTAssertTrue(model.selection.contains(items[1]))
        model.toggleSelect(items[1])
        XCTAssertFalse(model.selection.contains(items[1]))
    }

    func testToggleSelectIgnoresParentRow() throws {
        _ = try makeFile("a.txt")
        let model = PaneModel(directory: tmp)
        let parent = model.entries.first(where: { $0.isParent })!.url
        model.toggleSelect(parent)
        XCTAssertFalse(model.selection.contains(parent),
                       "parent (..) row must never be selectable")
    }

    func testSelectAllExcludesParent() throws {
        let (model, items) = try seedStandardFixture()
        model.selectAll()
        XCTAssertEqual(model.selection, Set(items))
    }

    func testSelectRangeInclusive() throws {
        let (model, items) = try seedStandardFixture()
        model.selectRange(from: items[0], to: items[2])
        XCTAssertEqual(model.selection, Set([items[0], items[1], items[2]]))
    }

    func testSelectRangeReverseDirection() throws {
        let (model, items) = try seedStandardFixture()
        model.selectRange(from: items[3], to: items[1])
        XCTAssertEqual(model.selection, Set([items[1], items[2], items[3]]),
                       "selectRange should be order-independent")
    }

    func testSelectRangeExcludesParent() throws {
        let (model, items) = try seedStandardFixture()
        let parent = model.entries.first(where: { $0.isParent })!.url
        model.selectRange(from: parent, to: items[1])
        XCTAssertFalse(model.selection.contains(parent))
        XCTAssertTrue(model.selection.contains(items[0]))
        XCTAssertTrue(model.selection.contains(items[1]))
    }

    func testMoveCursorExtendingBuildsSelection() throws {
        let (model, items) = try seedStandardFixture()
        model.cursor = items[0]
        model.moveCursorExtending(delta: 2)
        XCTAssertEqual(model.cursor, items[2])
        XCTAssertEqual(model.selection, Set([items[0], items[1], items[2]]))
    }

    // MARK: actionTargets

    func testActionTargetsReturnsSelectionWhenPresent() throws {
        let (model, items) = try seedStandardFixture()
        model.toggleSelect(items[0])
        model.toggleSelect(items[2])
        model.cursor = items[1]  // cursor on a different row

        let targets = Set(model.actionTargets())
        XCTAssertEqual(targets, Set([items[0], items[2]]),
                       "selection takes precedence over cursor")
    }

    func testActionTargetsReturnsCursorWhenNoSelection() throws {
        let (model, items) = try seedStandardFixture()
        model.cursor = items[1]

        XCTAssertEqual(model.actionTargets(), [items[1]])
    }

    func testActionTargetsExcludesParentCursor() throws {
        _ = try makeFile("a.txt")
        let model = PaneModel(directory: tmp)
        let parent = model.entries.first(where: { $0.isParent })!.url
        model.cursor = parent

        XCTAssertTrue(model.actionTargets().isEmpty,
                      "cursor on parent row produces no action targets")
    }

    // MARK: navigate + goUp

    func testNavigateChangesDirectoryAndClearsState() throws {
        _ = try makeFile("a.txt")
        let sub = try makeDir("sub")
        _ = try makeFile("inside.txt", in: sub)
        let model = PaneModel(directory: tmp)
        model.toggleSelect(model.entries.first(where: { !$0.isParent })!.url)
        XCTAssertFalse(model.selection.isEmpty)

        model.navigate(to: sub)

        XCTAssertEqual(model.directory.standardizedFileURL.path, sub.standardizedFileURL.path)
        XCTAssertTrue(model.selection.isEmpty, "selection cleared on navigate")
        XCTAssertTrue(model.entries.contains { $0.name == "inside.txt" })
    }

    func testGoUpRestoresCursorOnPreviousDirectory() throws {
        _ = try makeDir("sub")
        let model = PaneModel(directory: tmp)
        // Use the canonical URL that came from contentsOfDirectory (with any
        // trailing slash) so navigate→goUp lands on the matching entry.
        let subURL = model.entries.first { $0.name == "sub" }!.url
        _ = try makeFile("inside.txt", in: subURL)

        model.navigate(to: subURL)
        XCTAssertEqual(model.directory.standardizedFileURL.path,
                       subURL.standardizedFileURL.path)

        model.goUp()

        XCTAssertEqual(model.directory.standardizedFileURL.path,
                       tmp.standardizedFileURL.path)
        XCTAssertEqual(model.cursor?.standardizedFileURL.path,
                       subURL.standardizedFileURL.path,
                       "after goUp, cursor lands on the directory we came from")
    }

    // MARK: reload preserves selection of still-existing entries

    func testReloadDropsSelectionForDeletedEntries() throws {
        _ = try makeFile("a.txt")
        _ = try makeFile("b.txt")
        let model = PaneModel(directory: tmp)
        // Pull URLs from model.entries to get the canonical form FileManager uses.
        let f1 = model.entries.first { $0.name == "a.txt" }!.url
        let f2 = model.entries.first { $0.name == "b.txt" }!.url
        model.toggleSelect(f1)
        model.toggleSelect(f2)
        XCTAssertEqual(model.selection, Set([f1, f2]))

        try fm.removeItem(at: f1)
        model.reload()

        XCTAssertEqual(model.selection, Set([f2]),
                       "selection should drop URLs that no longer exist")
    }
}
