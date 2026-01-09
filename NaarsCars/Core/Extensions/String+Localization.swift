//
//  String+Localization.swift
//  NaarsCars
//
//  Extension for localized string access
//

import Foundation

extension String {
    /// Returns localized string using self as key
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
    
    /// Returns localized string with format arguments
    func localized(with arguments: CVarArg...) -> String {
        return String(format: self.localized, arguments: arguments)
    }
}

