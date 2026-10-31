import XCTest
@testable import LegadoReader

final class BackupFileExporterTests: XCTestCase {
    @MainActor
    func testPreparedFileAndJSONDecodeTheSameIsolatedStoreSnapshot() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let book = fixture.storage.addBookToShelf(Book(title: "导出测试", author: "作者",
            sourceUrl: "https://fixture.invalid", sourceName: "Fixture", bookUrl: "https://fixture.invalid/book"))
        fixture.storage.updateBookProgress(bookId: book.id, chapterIndex: 3, chapterTitle: "第四章",
            totalChapters: 20, paragraphIndex: 4, characterOffset: 125)
        fixture.storage.readerConfig.effectiveTapMode = .leftHanded
        fixture.storage.readerConfig.setTypography(ReaderTypography(fontSize: 25, lineSpacing: 14), for: .wide)
        fixture.storage.saveConfig()
        let snapshot = fixture.storage.makeFullBackupPayload()
        _ = fixture.storage.addBookToShelf(Book(title: "快照后加入", author: "作者",
            sourceUrl: "https://fixture.invalid", sourceName: "Fixture", bookUrl: "https://fixture.invalid/later"))

        let exporter = BackupFileExporter()
        let prepared = try await exporter.prepare(snapshot, directory: fixture.directory)
        let data = try Data(contentsOf: prepared.url)
        XCTAssertEqual(data, Data(prepared.json.utf8))
        let decoded = try JSONDecoder().decode(StorageManager.FullBackupPayload.self, from: data)
        XCTAssertEqual(decoded.bookshelf.count, 1, "Background export must use the captured snapshot")
        XCTAssertEqual(decoded.bookshelf.first?.currentCharacterOffset, 125)
        XCTAssertEqual(decoded.readerConfig.effectiveTapMode, .leftHanded)
        XCTAssertEqual(decoded.readerConfig.typography(for: .wide).fontSize, 25)
        XCTAssertEqual(decoded.readerConfigUpdatedAt, snapshot.readerConfigUpdatedAt)
        XCTAssertEqual(decoded.positionMap, snapshot.positionMap)
        let readBack = try await exporter.read(prepared.url)
        XCTAssertEqual(readBack, prepared.json)
    }

    @MainActor
    func testUnwritableDestinationThrowsAndDoesNotReturnAFakeURL() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let blocked = fixture.directory.appendingPathComponent("file-cannot-be-a-directory")
        let marker = Data("unchanged".utf8)
        try marker.write(to: blocked)
        let exporter = BackupFileExporter()
        do {
            _ = try await exporter.prepare(fixture.storage.makeFullBackupPayload(), directory: blocked)
            XCTFail("An unwritable destination must fail, not report a backup URL")
        } catch {
            XCTAssertTrue(error is CocoaError || (error as NSError).domain == NSCocoaErrorDomain)
        }
        XCTAssertEqual(try Data(contentsOf: blocked), marker)
        let files = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.map(\.lastPathComponent), [blocked.lastPathComponent])
    }

    @MainActor
    func testEachSuccessfulExportUsesItsOwnFile() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let payload = fixture.storage.makeFullBackupPayload()
        let exporter = BackupFileExporter()
        let first = try await exporter.prepare(payload, directory: fixture.directory)
        let second = try await exporter.prepare(payload, directory: fixture.directory)
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertEqual(try Data(contentsOf: first.url), try Data(contentsOf: second.url))
    }

    @MainActor
    func testCancelledPreparationWritesNoFile() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let payload = fixture.storage.makeFullBackupPayload()
        let exporter = BackupFileExporter()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await exporter.prepare(payload, directory: fixture.directory)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled export must not report success")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    @MainActor
    private final class Fixture {
        let defaults: UserDefaults
        let directory: URL
        let storage: StorageManager
        private let suite: String
        init() throws {
            suite = "BackupFileExporterTests.\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
            // Keep the cache elsewhere so directory contents reflect only exported files.
            storage = StorageManager(defaults: defaults, cacheDirectoryURL: directory.appendingPathComponent("cache"),
                                     loadDefaults: false, onBookRemoval: { _ in })
            try FileManager.default.removeItem(at: directory.appendingPathComponent("cache"))
        }
        func close() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
