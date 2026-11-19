import Darwin
import FilewiseCore
import Foundation

@main @MainActor struct ScanBenchmark {
    static func wait(_ library: Library) -> Bool {
        let deadline = Date().addingTimeInterval(180)
        while library.scanning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return !library.scanning
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("filewise-benchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let count = Int(ProcessInfo.processInfo.environment["FILEWISE_BENCHMARK_FILES"] ?? "10000") ?? 10000
        guard count > 0 && count <= 100000 else { fatalError("FILEWISE_BENCHMARK_FILES must be between 1 and 100000") }
        for i in 0..<count {
            // Unique sizes avoid measuring duplicate hashing for this metadata baseline.
            let file = root.appendingPathComponent("file-\(i).txt")
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: UInt64(i + 1))
            try handle.close()
        }
        let library = Library()
        let initial = Date()
        library.scan(root)
        guard wait(library), library.files.count == count, !library.indexUnavailable else { fatalError("Initial scan failed") }
        let initialSeconds = Date().timeIntervalSince(initial)
        let refresh = Date()
        library.scan(root)
        guard wait(library), library.files.count == count, !library.indexUnavailable else { fatalError("Refresh failed") }
        let refreshSeconds = Date().timeIntervalSince(refresh)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print(String(format: "Files: %d; initial scan: %.2f s; unchanged refresh: %.2f s; peak RSS: %.1f MiB", count, initialSeconds, refreshSeconds, Double(usage.ru_maxrss) / 1_048_576))
    }
}
