import Foundation

/// Captured when work starts. Deleting, re-adding or replacing a source cannot make
/// an older request eligible to write again, even when the persistent book ID is reused.
public struct BookWriteToken: Equatable {
    let bookID: String
    let logicalKey: String
    let generation: UUID
    let sourceURL: String
    let bookURL: String
}

public enum BackupSourcePolicy: String, CaseIterable { case keepLocal, useBackup }
public enum BackupConfigPolicy: String, CaseIterable { case newest, keepLocal, useBackup }
