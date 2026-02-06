//
//  LocalizationManager.swift
//  NaarsCars
//
//  Manages app language preferences and locale-aware formatting
//

import Foundation
import SwiftUI
internal import Combine

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
        AppLanguage(code: "zh-Hant", name: "Chinese (Traditional)", localizedName: "繁體中文"),
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
        
        // Set AppleLanguages to override system language
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            // Set the language preference
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            // Also set it in standardUserDefaults for immediate effect
            UserDefaults.standard.synchronize()
        }
        
        // Post notification for immediate updates where possible
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        
        AppLogger.info("localization", "Language set to: \(code)")
    }
    
    /// Initialize language preference on app launch
    /// This must be called before any UI is rendered to take effect
    func initializeLanguagePreference() {
        // Ensure AppleLanguages is set based on appLanguage preference
        // This must be set before Bundle.main loads any resources
        if appLanguage != "system" {
            // Set the language preference array
            // iOS will use this to determine which .lproj folder to use
            UserDefaults.standard.set([appLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            
            AppLogger.info("localization", "Initialized language preference: \(appLanguage)")
            if let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] {
                AppLogger.info("localization", "AppleLanguages set to: \(languages)")
            }
        } else {
            // Use system language - remove custom override
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            AppLogger.info("localization", "Using system language")
        }
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

