//
//  LoginViewModel.swift
//  NaarsCars
//
//  ViewModel for login view
//

import Foundation
internal import Combine

/// ViewModel for login view
@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    private let authService: any AuthServiceProtocol
    private let rateLimiter = RateLimiter.shared

    init(authService: any AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }
    
    /// Friendly, localized text for `error`. Never the raw system description.
    var errorMessage: String? {
        guard let error else { return nil }
        return AuthErrorMessage.text(for: error, fallbackKey: "auth_error_sign_in_failed")
    }

    func login() async {
        // A pasted or autofilled address often carries a trailing space, which the server
        // rejects as a wrong email.
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate email
        guard !trimmedEmail.isEmpty else {
            error = AppError.invalidInput("auth_error_email_required".localized)
            return
        }
        
        // Validate password
        guard !password.isEmpty else {
            error = AppError.invalidInput("auth_error_password_required".localized)
            return
        }
        
        // Check rate limit: 2 seconds between login attempts
        let canProceed = await rateLimiter.checkAndRecord(
            action: "login_attempt",
            minimumInterval: Constants.RateLimits.login
        )
        
        guard canProceed else {
            error = AppError.rateLimitExceeded("auth_error_rate_limited".localized)
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            try await authService.signIn(email: trimmedEmail, password: password)
            // Trigger AppLaunchManager to re-check auth state after successful login
            await AppLaunchManager.shared.performCriticalLaunch()
            HapticManager.success()
            // Navigation will be handled by ContentView based on auth state
        } catch {
            HapticManager.error()
            self.error = AuthErrorMessage.appError(from: error)
        }

        isLoading = false
    }
}

// MARK: - Friendly auth error text

/// Turns auth failures into friendly, localized text for the sign-in, sign-up and account
/// screens. `AppError`'s own descriptions are English-only and several wrap raw system text
/// ("Processing error: The Internet connection appears to be offline.. Please try again.").
enum AuthErrorMessage {

    /// Keeps an `AppError` as thrown and classifies anything else, so a dropped connection is
    /// reported as one instead of as an unknown error.
    static func appError(from error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        if isConnectivityFailure(error) {
            return .networkUnavailable
        }
        return .unknown(error.localizedDescription)
    }

    /// Localized text to show for `error`.
    /// - Parameter fallbackKey: Localization key of the sentence used when the error carries
    ///   nothing the user can act on.
    static func text(for error: AppError, fallbackKey: String) -> String {
        switch error {
        case .networkUnavailable:
            return "auth_error_offline".localized
        case .invalidCredentials:
            return "auth_error_invalid_credentials".localized
        case .emailAlreadyExists:
            return "signup_error_email_exists".localized
        case .invalidInviteCode:
            return "signup_error_invalid_or_expired_code".localized
        case .rateLimited:
            return "auth_error_rate_limited".localized
        case .invalidInput(let message), .rateLimitExceeded(let message):
            // Built from localized keys by the auth view models
            return message
        case .processingError(let message), .unknown(let message), .serverError(let message):
            // These wrap raw system or server text. Recognise the two cases a user can act
            // on and use a plain sentence for everything else.
            let lowered = message.lowercased()
            if lowered.contains("confirm") && lowered.contains("email") {
                return "auth_error_email_not_confirmed".localized
            }
            if !NetworkMonitor.shared.isConnected || mentionsConnectivity(lowered) {
                return "auth_error_offline".localized
            }
            return fallbackKey.localized
        default:
            return fallbackKey.localized
        }
    }

    /// True when `error` is a transport failure rather than an answer from the server
    static func isConnectivityFailure(_ error: Error) -> Bool {
        if !NetworkMonitor.shared.isConnected {
            return true
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        let transportCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorDataNotAllowed,
            NSURLErrorInternationalRoamingOff
        ]
        return transportCodes.contains(nsError.code)
    }

    /// Catches a connectivity failure that a service already flattened into message text
    private static func mentionsConnectivity(_ loweredMessage: String) -> Bool {
        ["offline", "internet connection", "network connection", "timed out", "could not connect"]
            .contains { loweredMessage.contains($0) }
    }
}



