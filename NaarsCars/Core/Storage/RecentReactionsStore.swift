import Foundation

/// Persists the user's recently used emoji reactions via UserDefaults.
/// Maintains an ordered list of up to `maxRecents` emoji, most recent first.
enum RecentReactionsStore {
    private static let key = "com.naarscars.recentReactions"
    private static let maxRecents = 15

    /// Returns the list of recently used emoji, most recent first.
    /// Excludes any emoji that appear in `MessageReaction.standardTapbacks`.
    static var recents: [String] {
        let all = UserDefaults.standard.stringArray(forKey: key) ?? []
        let standard = Set(MessageReaction.standardTapbacks)
        return all.filter { !standard.contains($0) }
    }

    /// Records an emoji as recently used. Moves it to the front if already present.
    /// Standard tapbacks are not recorded (they are always shown in the picker).
    static func record(_ emoji: String) {
        let standard = Set(MessageReaction.standardTapbacks)
        guard !standard.contains(emoji) else { return }

        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == emoji }
        list.insert(emoji, at: 0)
        if list.count > maxRecents {
            list = Array(list.prefix(maxRecents))
        }
        UserDefaults.standard.set(list, forKey: key)
    }
}
