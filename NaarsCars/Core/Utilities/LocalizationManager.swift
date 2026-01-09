//
//  LocalizationManager.swift
//  NaarsCars
//
//  Manages app language preferences and locale-aware formatting
//

import Foundation
import SwiftUI

/// Manager for app localization and language preferences
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @AppStorage("app_language") var appLanguage: String = "system"
    
    /// Available languages in the app
    static let supportedLanguages: [AppLanguage] = [
        AppLanguage(code: "system", name: "System Default", localizedName: "System Default"),
        AppLanguage(code: "en", name: "English", localizedName: "English"),
        AppLanguage(code: "es", name: "Spanish", localizedName: "Español"),
        AppLanguage(code: "zh-Hans", name: "Chinese (Simplified)", localizedName: "简体中文"),
        AppLanguage(code: "vi", name: "Vietnamese", localizedName: "Tiếng Việt"),
        AppLanguage(code: "ko", name: "Korean", localizedName: "한국어")
    ]
    
    /// Current locale to use for formatting
    var currentLocale: Locale {
        if appLanguage == "system" {
            return Locale.current
        }
        return Locale(identifier: appLanguage)
    }
    
    /// Current language code
    var currentLanguageCode: String {
        if appLanguage == "system" {
            return Locale.current.language.languageCode?.identifier ?? "en"
        }
        return appLanguage
    }
    
    private init() {}
    
    /// Apply language change (requires app restart for full effect)
    func setLanguage(_ code: String) {
        appLanguage = code
        
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        
        // Post notification for immediate updates where possible
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
}

/// Represents an available app language
struct AppLanguage: Identifiable {
    let code: String
    let name: String        // English name
    let localizedName: String  // Native name
    
    var id: String { code }
}

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}

