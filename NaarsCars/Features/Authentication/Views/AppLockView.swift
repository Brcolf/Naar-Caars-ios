//
//  AppLockView.swift
//  NaarsCars
//
//  Lock screen view for biometric authentication.
//  Pure UI — all state and auth logic lives in AppLockManager.
//

import SwiftUI

/// Lock screen view for biometric authentication
struct AppLockView: View {
    let lockManager: AppLockManager

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
                        await lockManager.unlock()
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
                .disabled(lockManager.state == .authenticating)
                .accessibilityLabel("Unlock with \(biometricService.biometricType.displayName)")
                .accessibilityHint("Double-tap to authenticate and unlock the app")
                .padding(.horizontal)

                Spacer()
                    .frame(height: 60)
            }
            .padding()
        }
        .alert(
            "app_lock_auth_failed".localized,
            isPresented: Binding(
                get: { lockManager.lastError != nil },
                set: { if !$0 { lockManager.clearError() } }
            )
        ) {
            Button("app_lock_try_again".localized) {
                Task { await lockManager.unlock() }
            }
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(lockManager.lastError?.errorDescription ?? "app_lock_please_try_again".localized)
        }
        .task {
            // Auto-prompt once on appear, only if still in .locked state
            guard lockManager.state == .locked else { return }
            await lockManager.unlock()
        }
    }
}

#Preview {
    AppLockView(lockManager: AppLockManager.shared)
}
