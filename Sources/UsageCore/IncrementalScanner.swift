import Foundation

/// Dosya başına okuma durumu. Loglar yalnızca sona eklenir; bu yüzden yalnızca yeni baytlar okunur.
public struct FileScanState: Codable, Hashable, Sendable {
    public var inode: UInt64
    public var offset: UInt64
    public var lastTimestamp: Date?
}

/// `root` altındaki tüm `*.jsonl` dosyalarını artımlı olarak tarar.
/// - Yarım kalmış son satır (yazma sürerken) bir sonraki taramaya bırakılır.
/// - Dosya küçülür veya inode değişirse baştan okunur (tekilleştirme çift sayımı önler).
public final class IncrementalScanner {
    public private(set) var states: [String: FileScanState]
    public private(set) var malformedLines = 0
    private let parser = LogParser()
    private let chunkSize: Int

    public init(states: [String: FileScanState] = [:], chunkSize: Int = 4 << 20) {
        self.states = states
        self.chunkSize = chunkSize
    }

    public func scan(roots: [URL]) -> [LogParser.Item] {
        var items: [LogParser.Item] = []
        var seen = Set<String>()
        for root in roots {
            for file in Self.jsonlFiles(under: root) {
                seen.insert(file.path)
                scanFile(file, into: &items)
            }
        }
        // Silinen dosyaların durumunu unut (önceden sayılan girdiler önbellekte kalır).
        for path in states.keys where !seen.contains(path) { states[path] = nil }
        return items
    }

    public func scanFile(_ url: URL, into items: inout [LogParser.Item]) {
        let path = url.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else { return }
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0

        var state = states[path] ?? FileScanState(inode: inode, offset: 0, lastTimestamp: nil)
        if state.inode != inode || size < state.offset {
            state = FileScanState(inode: inode, offset: 0, lastTimestamp: nil)
        }
        guard size > state.offset, let handle = try? FileHandle(forReadingFrom: url) else {
            states[path] = state
            return
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.offset)
            var pending = Data()
            var consumed = state.offset
            while true {
                let chunk = try handle.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty { break }
                pending.append(chunk)
                var lineStart = pending.startIndex
                while let nl = pending[lineStart...].firstIndex(of: 0x0A) {
                    let line = pending[lineStart..<nl]
                    if !line.isEmpty { process(line: Data(line), state: &state, items: &items) }
                    lineStart = pending.index(after: nl)
                }
                consumed += UInt64(lineStart - pending.startIndex)
                pending = Data(pending[lineStart...])
            }
            state.offset = consumed
        } catch {
            // Okuma hatası: mevcut ilerlemeyi koru, sonraki taramada tekrar denenir.
        }
        states[path] = state
    }

    private func process(line: Data, state: inout FileScanState, items: inout [LogParser.Item]) {
        switch parser.parse(line: line, fallbackTimestamp: state.lastTimestamp) {
        case .item(let item):
            if case .usage(let e) = item { state.lastTimestamp = max(state.lastTimestamp ?? e.timestamp, e.timestamp) }
            items.append(item)
        case .malformed:
            malformedLines += 1
        case .skipped:
            break
        }
    }

    static func jsonlFiles(under root: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            out.append(url)
        }
        return out.sorted { $0.path < $1.path }
    }
}
