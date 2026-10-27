import Foundation
import Testing
@testable import UsageCore

@Suite struct ScannerTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usagebar-tests-\(UUID().uuidString)/projects/-Users-test-proj")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func line(_ id: String, _ ts: String, out: Int = 10) -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","requestId":"r-\#(id)","sessionId":"s","message":{"id":"\#(id)","model":"claude-opus-5-5","usage":{"input_tokens":1,"output_tokens":\#(out),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
    }

    private func append(_ s: String, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data(s.utf8))
        try h.close()
    }

    @Test func readsOnlyNewBytesAndWaitsForPartialLine() throws {
        let dir = try tempDir()
        let root = dir.deletingLastPathComponent()
        let file = dir.appendingPathComponent("s.jsonl")
        let scanner = IncrementalScanner(chunkSize: 64) // küçük parça → parça sınırları test edilir

        try append(line("a", "2026-10-01T10:00:00Z") + "\n", to: file)
        #expect(scanner.scan(roots: [root]).count == 1)
        #expect(scanner.scan(roots: [root]).count == 0) // değişiklik yok

        // Yarım satır: henüz sayılmamalı
        let second = line("b", "2026-10-01T10:01:00Z")
        let cut = second.index(second.startIndex, offsetBy: 40)
        try append(String(second[..<cut]), to: file)
        #expect(scanner.scan(roots: [root]).count == 0)
        #expect(scanner.malformedLines == 0)

        try append(String(second[cut...]) + "\n", to: file)
        let items = scanner.scan(roots: [root])
        #expect(items.count == 1)
        if case .usage(let e) = items.first { #expect(e.key == "b:r-b") }
    }

    @Test func truncatedFileIsRescannedAndDedupeAvoidsDoubleCount() throws {
        let dir = try tempDir()
        let root = dir.deletingLastPathComponent()
        let file = dir.appendingPathComponent("s.jsonl")
        let scanner = IncrementalScanner()
        var store = UsageStore()

        try append(line("a", "2026-10-01T10:00:00Z") + "\n" + line("b", "2026-10-01T10:01:00Z") + "\n", to: file)
        store.ingest(scanner.scan(roots: [root]))
        #expect(store.entries.count == 2)

        try Data((line("a", "2026-10-01T10:00:00Z") + "\n").utf8).write(to: file) // küçüldü
        store.ingest(scanner.scan(roots: [root]))
        #expect(store.entries.count == 2)
    }

    @Test func scansNestedDirectoriesAndIgnoresOtherFiles() throws {
        let dir = try tempDir()
        let root = dir.deletingLastPathComponent()
        let nested = dir.appendingPathComponent("sess/subagents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try append(line("a", "2026-10-01T10:00:00Z") + "\n", to: dir.appendingPathComponent("s.jsonl"))
        try append(line("b", "2026-10-01T10:00:00Z") + "\n", to: nested.appendingPathComponent("agent.jsonl"))
        try append(line("c", "2026-10-01T10:00:00Z") + "\n", to: dir.appendingPathComponent("notes.txt"))
        #expect(IncrementalScanner().scan(roots: [root]).count == 2)
    }

    @Test func engineCacheRoundTrip() async throws {
        let dir = try tempDir()
        let root = dir.deletingLastPathComponent()
        let file = dir.appendingPathComponent("s.jsonl")
        let cache = root.appendingPathComponent("cache.json")
        try append(line("a", "2026-10-01T10:00:00Z", out: 100) + "\n", to: file)

        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let s1 = await UsageEngine(roots: [root], cacheURL: cache).refresh(pricing: .default, now: now)
        #expect(s1.entryCount == 1)

        // Yeni motor önbellekten yükler; dosyaya eklenen satırı da görür
        try append(line("b", "2026-10-01T11:00:00Z", out: 100) + "\n", to: file)
        let s2 = await UsageEngine(roots: [root], cacheURL: cache).refresh(pricing: .default, now: now)
        #expect(s2.entryCount == 2)
    }
}
