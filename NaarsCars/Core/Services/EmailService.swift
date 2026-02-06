//
//  EmailService.swift
//  NaarsCars
//
//  Service for sending email notifications
//  Uses Supabase Edge Functions or third-party email service
//

import Foundation
import Supabase

/// Service for sending email notifications
@MainActor
final class EmailService {
    
    // MARK: - Singleton
    
    static let shared = EmailService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Email Operations
    
    /// Send welcome email to a newly approved user
    /// - Parameters:
    ///   - userId: The user ID who was approved
    ///   - email: The user's email address
    ///   - name: The user's name
    /// - Throws: AppError if sending fails
    func sendWelcomeEmail(userId: UUID, email: String, name: String) async throws {
        // For now, we'll use a Supabase Edge Function to send emails
        // This requires an Edge Function to be deployed
        // NOTE: Email sending requires deploying a Supabase Edge Function (e.g., using Resend or SendGrid)
        
        // Call Edge Function to send email
        // The Edge Function will handle the actual email sending
        struct EmailPayload: Codable {
            let userId: String
            let email: String
            let name: String
            let type: String
            
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case email
                case name
                case type
            }
        }
        
        let payload = EmailPayload(
            userId: userId.uuidString,
            email: email,
            name: name,
            type: "welcome"
        )
        
        // Call Edge Function (if it exists)
        // For now, we'll just log that email should be sent
        // In production, this would call: supabase.functions.invoke("send-email", body: payload)
        AppLogger.info("email", "Would send welcome email to: \(email) for user: \(name)")
        
        // NOTE: Email sending requires deploying a Supabase Edge Function (e.g., using Resend or SendGrid)
        /*
        try await supabase.functions.invoke(
            "send-email",
            options: FunctionInvokeOptions(
                body: payload
            )
        )
        */
    }
}


