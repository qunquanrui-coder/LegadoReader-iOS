import Foundation

struct PreparedBackup {
    let json: String
    let url: URL
}

/// Serialization and file writes are requested by an action, never from a SwiftUI body.
actor BackupFileExporter {
    func prepare(_ payload: StorageManager.FullBackupPayload, directory: URL = FileManager.default.temporaryDirectory) throws -> PreparedBackup {
        try Task.checkCancellation()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try Task.checkCancellation()
        let url = directory.appendingPathComponent("风读全量备份_\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return PreparedBackup(json: String(decoding: data, as: UTF8.self), url: url)
    }

    func read(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        return try String(contentsOf: url, encoding: .utf8)
    }
}
