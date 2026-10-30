import Foundation

/// The first two values keep the on-disk position map readable by earlier versions.
/// UTF-16 offsets match the paginator and are optional for legacy, paragraph-only positions.
struct StoredReadingPosition: Equatable {
    let chapterIndex: Int
    let paragraphIndex: Int
    let characterOffset: Int

    init(chapterIndex: Int, paragraphIndex: Int, characterOffset: Int = 0) {
        self.chapterIndex = max(0, chapterIndex)
        self.paragraphIndex = max(0, paragraphIndex)
        self.characterOffset = max(0, characterOffset)
    }

    init?(values: [Int]) {
        guard values.count >= 2 else { return nil }
        self.init(chapterIndex: values[0], paragraphIndex: values[1],
                  characterOffset: values.count > 2 ? values[2] : 0)
    }

    var values: [Int] {
        let legacy = [chapterIndex, paragraphIndex]
        return characterOffset > 0 ? legacy + [characterOffset] : legacy
    }
}

/// Defaults injection lets persistence tests exercise property-list round trips without
/// reading or changing the app's real bookshelf or reading progress.
struct ReadingPositionStore {
    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String) {
        self.defaults = defaults
        self.key = key
    }

    func position(for bookKey: String) -> StoredReadingPosition? {
        guard let map = defaults.dictionary(forKey: key) as? [String: [Int]],
              let values = map[bookKey] else { return nil }
        return StoredReadingPosition(values: values)
    }

    func set(_ position: StoredReadingPosition, for bookKey: String) {
        var map = (defaults.dictionary(forKey: key) as? [String: [Int]]) ?? [:]
        map[bookKey] = position.values
        defaults.set(map, forKey: key)
    }
}
