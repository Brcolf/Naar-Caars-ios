//
//  AppTheme.swift
//  NaarsCars
//
//  Theme management for light/dark mode preferences
//

import SwiftUI
import UIKit
internal import Combine

// MARK: - Theme Mode

/// Available theme modes for the app
enum ThemeMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var id: String { rawValue }
    
    /// User-facing display name
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    /// SF Symbol icon for the theme
    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    /// Convert to UIUserInterfaceStyle
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Theme Manager

/// Manages app-wide theme settings and persistence
@MainActor
final class ThemeManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ThemeManager()
    
    // MARK: - Published Properties
    
    /// Current theme mode
    @Published var currentTheme: ThemeMode {
        didSet {
            saveTheme()
            applyTheme()
        }
    }
    
    // MARK: - Private Properties
    
    private let userDefaultsKey = "naars_theme_mode"
    
    // MARK: - Initialization
    
    private init() {
        // Load saved theme or default to system
        if let savedTheme = UserDefaults.standard.string(forKey: userDefaultsKey),
           let theme = ThemeMode(rawValue: savedTheme) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .system
        }
    }
    
    // MARK: - Public Methods
    
    /// Apply the current theme to all windows
    func applyTheme() {
        // Get all connected scenes and apply theme to their windows
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        
        for window in windowScene.windows {
            window.overrideUserInterfaceStyle = currentTheme.userInterfaceStyle
        }
    }
    
    /// Apply theme on app launch (call from NaarsCarsApp)
    func applyThemeOnLaunch() {
        // Apply after a brief delay to ensure windows are ready
        DispatchQueue.main.async { [weak self] in
            self?.applyTheme()
        }
    }
    
    /// Set theme mode
    func setTheme(_ mode: ThemeMode) {
        currentTheme = mode
    }
    
    // MARK: - Private Methods
    
    private func saveTheme() {
        UserDefaults.standard.set(currentTheme.rawValue, forKey: userDefaultsKey)
    }
}

// MARK: - SwiftUI Environment

/// Environment key for accessing theme manager
private struct ThemeManagerKey: EnvironmentKey {
    static let defaultValue = ThemeManager.shared
}

extension EnvironmentValues {
    var themeManager: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Apply theme manager to view hierarchy
    func withThemeManager() -> some View {
        self.environmentObject(ThemeManager.shared)
    }
}

