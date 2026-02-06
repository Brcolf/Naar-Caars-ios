//
//  AppLockView.swift
//  NaarsCars
//
//  Lock screen view for biometric authentication
//

import SwiftUI

/// Lock screen view for biometric authentication
struct AppLockView: View {
    @State private var isAuthenticating = false
    @State private var error: BiometricError?
    @State private var showError = false
    
    let onUnlock: () -> Void
    let onCancel: (() -> Void)?
    
    private let biometricService = BiometricService.shared
    
    var body: some View {
        ZStack {
            // Blurred background
            Color.naarsBackgroundSecondary
                .ignoresSafeArea()
                .opacity(0.95)
            
            VStack(spacing: 32) {
                Spacer()
                
                // App logo
                Image(systemName: "car.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.accentColor)
                    .accessibilityLabel("Naar's Cars logo")
                
                Text("app_lock_title".localized)
                    .font(.naarsTitle)
                    .fontWeight(.bold)
                
                Text("app_lock_subtitle".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Biometric button
                Button {
                    Task {
                        await authenticate()
                    }
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: biometricService.biometricType.iconName)
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        
                        Text(String(format: "app_lock_unlock_with".localized, biometricService.biometricType.displayName))
                            .font(.naarsHeadline)
                    }
                    .foregroundColor(.accentColor)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .disabled(isAuthenticating)
                .accessibilityLabel("Unlock with \(biometricService.biometricType.displayName)")
                .accessibilityHint("Double-tap to authenticate and unlock the app")
                .padding(.horizontal)
                
                if let onCancel {
                    Button("common_cancel".localized) {
                        onCancel()
                    }
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                }
                
                Spacer()
                    .frame(height: 60)
            }
            .padding()
        }
        .alert("app_lock_auth_failed".localized, isPresented: $showError) {
            Button("app_lock_try_again".localized) {
                Task {
                    await authenticate()
                }
            }
            if let onCancel {
                Button("common_cancel".localized, role: .cancel) {
                    onCancel()
                }
            } else {
                Button("common_ok".localized, role: .cancel) {}
            }
        } message: {
            Text(error?.errorDescription ?? "app_lock_please_try_again".localized)
        }
        .task {
            // Automatically prompt on appear
            await authenticate()
        }
    }
    
    private func authenticate() async {
        isAuthenticating = true
        error = nil
        
        do {
            let success = try await biometricService.authenticate(
                reason: "app_lock_biometric_reason".localized
            )
            
            if success {
                BiometricPreferences.shared.recordAuthentication()
                onUnlock()
            }
        } catch let biometricError as BiometricError {
            if case .cancelled = biometricError {
                // User cancelled - don't show error
                // If no onCancel handler, they must unlock
                if onCancel == nil {
                    // Keep locked, user must authenticate
                }
            } else {
                self.error = biometricError
                self.showError = true
            }
        } catch {
            self.error = .unknown(error.localizedDescription)
            self.showError = true
        }
        
        isAuthenticating = false
    }
}

#Preview {
    AppLockView(onUnlock: {
        AppLogger.info("auth", "Unlocked")
    }, onCancel: nil)
}


