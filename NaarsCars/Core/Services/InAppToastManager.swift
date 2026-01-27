//
//  InAppToastManager.swift
//  NaarsCars
//
//  Global in-app toast manager for message notifications
//

import Foundation
import UIKit
internal import Combine

@MainActor
final class InAppToastManager: ObservableObject {
    static let shared = InAppToastManager()

    @Published var latestToast: InAppMessageToast?

    private let notificationCenter: NotificationCenter
    private let appStateProvider: () -> UIApplication.State
    private let profileService: ProfileService
    private let authService: AuthService
    private var cancellables = Set<AnyCancellable>()
    private var activeConversationId: UUID?
    private var dismissTask: Task<Void, Never>?

    init(
        notificationCenter: NotificationCenter = .default,
        appStateProvider: @escaping () -> UIApplication.State = { UIApplication.shared.applicationState },
        profileService: ProfileService = .shared,
        authService: AuthService = .shared
    ) {
        self.notificationCenter = notificationCenter
        self.appStateProvider = appStateProvider
        self.profileService = profileService
        self.authService = authService
        setupObservers()
    }

    private func setupObservers() {
        notificationCenter.publisher(for: .messageThreadDidAppear)
            .compactMap { $0.userInfo?["conversationId"] as? UUID }
            .sink { [weak self] conversationId in
                self?.activeConversationId = conversationId
                self?.clearToast()
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: .messageThreadDidDisappear)
            .sink { [weak self] _ in
                self?.activeConversationId = nil
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: NSNotification.Name("conversationUpdated"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleConversationUpdated(notification)
            }
            .store(in: &cancellables)
    }

    private func handleConversationUpdated(_ notification: Notification) {
        guard appStateProvider() == .active else { return }
        guard let message = notification.userInfo?["message"] as? Message else { return }
        guard let event = notification.userInfo?["event"] as? String, event == "insert" else { return }
        guard let currentUserId = authService.currentUserId, message.fromId != currentUserId else { return }
        if let activeConversationId, activeConversationId == message.conversationId {
            return
        }

        Task { [weak self] in
            let (senderName, senderAvatarUrl) = await self?.resolveSender(for: message) ?? ("Someone", nil)
            await self?.showToast(for: message, senderName: senderName, senderAvatarUrl: senderAvatarUrl)
        }
    }

    private func resolveSender(for message: Message) async -> (String, String?) {
        if let sender = message.sender {
            return (sender.name, sender.avatarUrl)
        }

        do {
            let profile = try await profileService.fetchProfile(userId: message.fromId)
            return (profile.name, profile.avatarUrl)
        } catch {
            return ("Someone", nil)
        }
    }

    private func showToast(for message: Message, senderName: String, senderAvatarUrl: String?) {
        latestToast = InAppMessageToast(
            id: message.id,
            conversationId: message.conversationId,
            messageId: message.id,
            senderName: senderName,
            senderAvatarUrl: senderAvatarUrl,
            messagePreview: toastPreviewText(for: message),
            receivedAt: Date()
        )
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                self?.latestToast = nil
            }
        }
    }

    private func clearToast() {
        dismissTask?.cancel()
        latestToast = nil
    }

    private func toastPreviewText(for message: Message) -> String {
        if message.isAudioMessage {
            return "Voice message"
        }
        if message.isLocationMessage {
            return message.locationName ?? "Shared location"
        }
        if message.imageUrl != nil && message.text.isEmpty {
            return "Photo"
        }
        return message.text
    }
}

struct InAppMessageToast: Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    let messageId: UUID
    let senderName: String
    let senderAvatarUrl: String?
    let messagePreview: String
    let receivedAt: Date
}

extension Notification.Name {
    static let messageThreadDidAppear = Notification.Name("messageThreadDidAppear")
    static let messageThreadDidDisappear = Notification.Name("messageThreadDidDisappear")
}
