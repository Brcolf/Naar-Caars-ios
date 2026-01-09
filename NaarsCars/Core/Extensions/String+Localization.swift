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
    /// 
    /// Note: This will work once localization files are added to the project.
    /// For now, it respects the AppleLanguages preference set by LocalizationManager.
    var localized: String {
        // Use NSLocalizedString which respects AppleLanguages UserDefaults
        // LocalizationManager sets this preference on app launch
        return NSLocalizedString(self, comment: "")
    }
    
    /// Returns localized string with format arguments
    func localized(with arguments: CVarArg...) -> String {
        return String(format: self.localized, arguments: arguments)
    }
}

