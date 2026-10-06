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
    
    /// The language preference the app launched with (this singleton is first created during
    /// app init). The strings on screen come from the bundle chosen at launch, so dates and
    /// numbers keep following this until the restart; switching them at once left dates in
    /// the new language beside text in the old one.
    private let launchLanguage: String

    /// Current locale to use for formatting
    var currentLocale: Locale {
        if launchLanguage == "system" {
            return Locale.current
        }
        return Locale(identifier: launchLanguage)
    }

    /// Current language code
    var currentLanguageCode: String {
        if launchLanguage == "system" {
            return Locale.current.language.languageCode?.identifier ?? "en"
        }
        return launchLanguage
    }

    private init() {
        // Same key and default as the `appLanguage` storage above
        launchLanguage = UserDefaults.standard.string(forKey: "app_language") ?? "system"
    }

    /// Apply language change (requires app restart for full effect)
    func setLanguage(_ code: String) {
        appLanguage = code

        // Set AppleLanguages to override system language
        if code == "system" {
            // The one place the override is removed: the person chose System Default here.
            // iOS then falls back to the device language, or to a per-app language picked
            // afterwards in the Settings app.
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            // Set the language preference
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            // Also set it in standardUserDefaults for immediate effect

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

            
            AppLogger.info("localization", "Initialized language preference: \(appLanguage)")
            if let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] {
                AppLogger.info("localization", "AppleLanguages set to: \(languages)")
            }
        } else {
            // System Default: leave AppleLanguages alone. iOS stores the per-app language
            // chosen in the Settings app under this same key, so removing it on every launch
            // erased that choice. An in-app override is removed in setLanguage("system"),
            // when the person switches back.
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

