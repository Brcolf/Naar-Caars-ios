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
        return localizedString
    }
    
    /// Returns localized string with format arguments
    func localized(with arguments: CVarArg...) -> String {
        return String(format: self.localized, arguments: arguments)
    }
}

