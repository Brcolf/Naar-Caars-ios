//
//  AppError.swift
//  NaarsCars
//
//  Centralized error types with user-friendly messages
//

import Foundation

/// App-wide error types with localized descriptions
/// Matches FR-040 from prd-foundation-architecture.md
enum AppError: LocalizedError {
    case networkUnavailable
    case serverError(String)
    case invalidCredentials
    case sessionExpired
    case notAuthenticated
    case authenticationRequired
    case invalidInviteCode
    case rateLimited
    case rateLimitExceeded(String)
    case emailAlreadyExists
    case requiredFieldMissing
    case invalidInput(String)
    case notFound(String)
    case unauthorized
    case permissionDenied(String)
    case processingError(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "No internet connection. Please check your network and try again."
        case .serverError(let message):
            return "Server error: \(message). Please try again later."
        case .invalidCredentials:
            return "Invalid email or password. Please check your credentials and try again."
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .authenticationRequired:
            return "Authentication is required to perform this action."
        case .invalidInviteCode:
            return "Invalid or expired invite code. Please check the code and try again."
        case .rateLimited:
            return "Please wait a moment before trying again."
        case .rateLimitExceeded(let message):
            return message
        case .emailAlreadyExists:
            return "An account with this email already exists."
        case .requiredFieldMissing:
            return "Please fill in all required fields."
        case .invalidInput(let message):
            return message
        case .notFound(let item):
            return "\(item) not found. It may have been deleted or moved."
        case .unauthorized:
            return "You don't have permission to perform this action."
        case .permissionDenied(let message):
            return message
        case .processingError(let message):
            return "Processing error: \(message). Please try again."
        case .unknown(let message):
            return "An unexpected error occurred: \(message). Please try again."
        }
    }
    
    var failureReason: String? {
        switch self {
        case .networkUnavailable:
            return "Network connection unavailable"
        case .serverError(let message):
            return message
        case .invalidCredentials:
            return "Invalid email or password"
        case .sessionExpired:
            return "Session expired"
        case .notAuthenticated:
            return "User not authenticated"
        case .authenticationRequired:
            return "Authentication required"
        case .invalidInviteCode:
            return "Invalid invite code"
        case .rateLimited:
            return "Rate limited"
        case .rateLimitExceeded(let message):
            return message
        case .emailAlreadyExists:
            return "Email already exists"
        case .requiredFieldMissing:
            return "Required field missing"
        case .invalidInput(let message):
            return message
        case .notFound(let item):
            return "\(item) not found"
        case .unauthorized:
            return "Unauthorized access"
        case .permissionDenied(let message):
            return message
        case .processingError(let message):
            return message
        case .unknown(let message):
            return message
        }
    }
}
