//
//  String+Localization.swift
//  NaarsCars
//
//  Extension for localized string access
//

import Foundation

extension String {
    /// Returns localized string using self as key
    /// Uses LocalizationManager to respect user's language preference
    /// Explicitly uses Bundle.main to ensure Localizable.xcstrings is found
    var localized: String {
        // Use NSLocalizedString with explicit bundle to ensure Localizable.xcstrings is found
        // The tableName "Localizable" corresponds to Localizable.xcstrings
        let localizedString = NSLocalizedString(self, tableName: "Localizable", bundle: .main, value: self, comment: "")
        guard localizedString == self else { return localizedString }
        // The lookup returns the key itself when the current language has no entry for it.
        // About 200 keys exist only in English; show the English text rather than an
        // identifier such as "welcome_title".
        return Self.englishBundle?.localizedString(forKey: self, value: self, table: "Localizable") ?? self
    }

    /// The English strings table, used when a key is missing from the current language.
    private static let englishBundle: Bundle? = Bundle.main
        .path(forResource: "en", ofType: "lproj")
        .flatMap { Bundle(path: $0) }
    
    /// Returns localized string with format arguments
    func localized(with arguments: CVarArg...) -> String {
        return String(format: self.localized, arguments: arguments)
    }
}

