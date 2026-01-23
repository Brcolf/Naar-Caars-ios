//
//  DevNotificationTestView.swift
//  NaarsCars
//
//  Dev-only view for testing push notifications locally
//

import SwiftUI
import UserNotifications

/// Dev tool for simulating push notifications locally
/// Add to admin panel for easy access during development
struct DevNotificationTestView: View {
    @State private var lastSent: String?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var badgePayload: String?
    @State private var isFetchingBadgePayload = false
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    var body: some View {
        List {
            // Status section
            Section {
                if let lastSent = lastSent {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Last sent: \(lastSent)")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Label("Dev Notification Tester", systemImage: "hammer.fill")
            } footer: {
                Text("Sends local notifications to test notification handling. Minimize app after tapping to see the notification.")
            }
            
            // Message notifications
            Section("Messages") {
                NotificationButton(
                    title: "New Message",
                    icon: "message.fill",
                    color: .blue
                ) {
                    await sendTestNotification(
                        type: "message",
                        title: "New Message",
                        body: "Hey! Just checking in about the ride tomorrow.",
                        userInfo: ["conversation_id": UUID().uuidString]
                    )
                }
                
                NotificationButton(
                    title: "Added to Conversation",
                    icon: "person.badge.plus",
                    color: .blue
                ) {
                    await sendTestNotification(
                        type: "added_to_conversation",
                        title: "New Conversation",
                        body: "You were added to a conversation with 3 people.",
                        userInfo: ["conversation_id": UUID().uuidString]
                    )
                }
            }
            
            // Ride notifications
            Section("Rides") {
                NotificationButton(
                    title: "New Ride Posted",
                    icon: "car.fill",
                    color: .naarsPrimary
                ) {
                    await sendTestNotification(
                        type: "new_ride",
                        title: "New Ride",
                        body: "John posted a ride to Airport",
                        userInfo: ["ride_id": UUID().uuidString]
                    )
                }
                
                NotificationButton(
                    title: "Ride Claimed",
                    icon: "hand.raised.fill",
                    color: .green
                ) {
                    await sendTestNotification(
                        type: "ride_claimed",
                        title: "Ride Claimed",
                        body: "Sarah claimed your ride to Downtown!",
                        userInfo: ["ride_id": UUID().uuidString]
                    )
                }
                
                NotificationButton(
                    title: "Ride Completed",
                    icon: "checkmark.circle.fill",
                    color: .green
                ) {
                    await sendTestNotification(
                        type: "ride_completed",
                        title: "Ride Completed",
                        body: "Your ride to Airport was marked complete.",
                        userInfo: ["ride_id": UUID().uuidString]
                    )
                }
            }
            
            // Favor notifications
            Section("Favors") {
                NotificationButton(
                    title: "New Favor Posted",
                    icon: "hand.raised.fill",
                    color: .orange
                ) {
                    await sendTestNotification(
                        type: "new_favor",
                        title: "New Favor",
                        body: "Mike needs help with grocery pickup",
                        userInfo: ["favor_id": UUID().uuidString]
                    )
                }
                
                NotificationButton(
                    title: "Favor Claimed",
                    icon: "person.fill.checkmark",
                    color: .green
                ) {
                    await sendTestNotification(
                        type: "favor_claimed",
                        title: "Favor Claimed",
                        body: "Emma claimed your favor request!",
                        userInfo: ["favor_id": UUID().uuidString]
                    )
                }
            }
            
            // Q&A notifications
            Section("Q&A") {
                NotificationButton(
                    title: "New Question",
                    icon: "questionmark.circle.fill",
                    color: .purple
                ) {
                    await sendTestNotification(
                        type: "qa_question",
                        title: "New Question",
                        body: "Alex asked: \"What time will you be leaving?\"",
                        userInfo: ["ride_id": UUID().uuidString]
                    )
                }
                
                NotificationButton(
                    title: "Answer Posted",
                    icon: "text.bubble.fill",
                    color: .purple
                ) {
                    await sendTestNotification(
                        type: "qa_answer",
                        title: "Question Answered",
                        body: "Your question was answered: \"Around 3pm\"",
                        userInfo: ["ride_id": UUID().uuidString]
                    )
                }
            }
            
            // Town Hall notifications
            Section("Town Hall") {
                NotificationButton(
                    title: "New Post",
                    icon: "building.columns.fill",
                    color: .indigo
                ) {
                    await sendTestNotification(
                        type: "town_hall_post",
                        title: "New Town Hall Post",
                        body: "Check out this new discussion about community events!",
                        userInfo: ["town_hall_post_id": UUID().uuidString]
                    )
                }
                
                NotificationButton(
                    title: "New Comment",
                    icon: "bubble.left.fill",
                    color: .indigo
                ) {
                    await sendTestNotification(
                        type: "town_hall_comment",
                        title: "New Comment",
                        body: "Someone commented on your post",
                        userInfo: ["town_hall_post_id": UUID().uuidString]
                    )
                }
            }
            
            // Admin notifications
            Section("Admin") {
                NotificationButton(
                    title: "Pending Approval",
                    icon: "person.badge.clock.fill",
                    color: .naarsWarning
                ) {
                    await sendTestNotification(
                        type: "pending_approval",
                        title: "New User Pending",
                        body: "A new user is waiting for approval",
                        userInfo: [:]
                    )
                }
                
                NotificationButton(
                    title: "User Approved",
                    icon: "checkmark.circle.fill",
                    color: .green
                ) {
                    await sendTestNotification(
                        type: "user_approved",
                        title: "Welcome!",
                        body: "Your account has been approved. Start exploring!",
                        userInfo: [:]
                    )
                }
            }
            
            // Special notifications
            Section("Special") {
                NotificationButton(
                    title: "Completion Reminder",
                    icon: "clock.fill",
                    color: .naarsWarning
                ) {
                    await sendCompletionReminderNotification()
                }
                
                NotificationButton(
                    title: "Announcement",
                    icon: "megaphone.fill",
                    color: .red
                ) {
                    await sendTestNotification(
                        type: "announcement",
                        title: "📢 Announcement",
                        body: "Important community update - please read!",
                        userInfo: [:]
                    )
                }
            }

            Section {
                Button {
                    Task {
                        isFetchingBadgePayload = true
                        do {
                            badgePayload = try await BadgeCountManager.shared.fetchBadgeCountsPayload()
                        } catch {
                            badgePayload = "Error: \(error.localizedDescription)"
                        }
                        isFetchingBadgePayload = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "tray.full")
                            .foregroundColor(.naarsPrimary)
                        Text("Fetch badge counts payload")
                        Spacer()
                        if isFetchingBadgePayload {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }

                if let badgePayload = badgePayload {
                    Text(badgePayload)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundColor(.secondary)
                } else {
                    Text("No payload fetched yet.")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Badge Counts RPC")
            } footer: {
                Text("Calls get_badge_counts RPC and shows raw JSON for QA.")
            }
        }
        .navigationTitle("Notification Tester")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Notification", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Send Test Notification
    
    private func sendTestNotification(
        type: String,
        title: String,
        body: String,
        userInfo: [String: String]
    ) async {
        // Check permission
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            await MainActor.run {
                alertMessage = "Notification permission not granted. Enable in Settings."
                showingAlert = true
            }
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        var info: [String: Any] = ["type": type]
        for (key, value) in userInfo {
            info[key] = value
        }
        content.userInfo = info
        
        // Send after 2 second delay to give time to minimize
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let identifier = "dev-test-\(type)-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            await MainActor.run {
                lastSent = title
            }
            print("✅ [DevTest] Sent test notification: \(type)")
        } catch {
            await MainActor.run {
                alertMessage = "Failed to send: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
    
    private func sendCompletionReminderNotification() async {
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            await MainActor.run {
                alertMessage = "Notification permission not granted. Enable in Settings."
                showingAlert = true
            }
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Is This Complete?"
        content.body = "Did you complete the ride to Airport?"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.completionReminder.rawValue
        content.userInfo = [
            "type": "completion_reminder",
            "reminder_id": UUID().uuidString,
            "ride_id": UUID().uuidString,
            "actionable": true
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let identifier = "dev-test-completion-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            await MainActor.run {
                lastSent = "Completion Reminder (with actions)"
            }
        } catch {
            await MainActor.run {
                alertMessage = "Failed to send: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

// MARK: - Notification Button Component

private struct NotificationButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () async -> Void
    
    @State private var isSending = false
    
    var body: some View {
        Button {
            Task {
                isSending = true
                await action()
                try? await Task.sleep(nanoseconds: 500_000_000)
                isSending = false
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 24)
                
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSending {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "bell.badge")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .disabled(isSending)
    }
}

#Preview {
    NavigationView {
        DevNotificationTestView()
    }
}

