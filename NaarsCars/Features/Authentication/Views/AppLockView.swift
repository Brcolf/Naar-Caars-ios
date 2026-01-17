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
            Color(.systemBackground)
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
                
                Text("Naar's Cars")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Unlock to continue")
                    .font(.subheadline)
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
                        
                        Text("Unlock with \(biometricService.biometricType.displayName)")
                            .font(.headline)
                    }
                    .foregroundColor(.accentColor)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .disabled(isAuthenticating)
                .padding(.horizontal)
                
                if let onCancel {
                    Button("Cancel") {
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
        .alert("Authentication Failed", isPresented: $showError) {
            Button("Try Again") {
                Task {
                    await authenticate()
                }
            }
            if let onCancel {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(error?.errorDescription ?? "Please try again.")
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
                reason: "Unlock Naar's Cars"
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
        print("Unlocked!")
    }, onCancel: nil)
}


