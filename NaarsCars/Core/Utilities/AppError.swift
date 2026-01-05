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
    case invalidInviteCode
    case notFound(String)
    case unauthorized
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
        case .invalidInviteCode:
            return "Invalid invite code. Please check the code and try again."
        case .notFound(let item):
            return "\(item) not found. It may have been deleted or moved."
        case .unauthorized:
            return "You don't have permission to perform this action."
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
        case .invalidInviteCode:
            return "Invalid invite code"
        case .notFound(let item):
            return "\(item) not found"
        case .unauthorized:
            return "Unauthorized access"
        case .unknown(let message):
            return message
        }
    }
}

