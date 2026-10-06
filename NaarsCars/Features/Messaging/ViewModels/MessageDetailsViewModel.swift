//
//  MessageDetailsViewModel.swift
//  NaarsCars
//
//  View model for the conversation details popup (title, group image, participants, mute, read receipts, leave)
//

import Foundation
import UIKit
import OSLog
import PostgREST
internal import Combine

/// Owns all mutations behind MessageDetailsPopup
@MainActor
final class MessageDetailsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var participants: [Profile]
    @Published var isSaving = false
    @Published var isLoadingParticipants = false
    @Published var isRemovingParticipant = false
    @Published var isUploadingImage = false
    @Published var error: String?
    @Published var isConversationMuted = false
    @Published var showReadReceiptsForConversation = true
    @Published var activeParticipantCount: Int = 0
    /// Members the current user has blocked (seeded from the local blocked-user cache, added to
    /// when a block from this sheet succeeds), and the block request's progress / failure
    @Published var blockedUserIds: Set<UUID> = []
    @Published var isBlocking = false
    @Published var blockError: String?

    // MARK: - Private Properties

    let conversationId: UUID
    private let conversationService: any ConversationServiceProtocol
    private let profileService: any ProfileServiceProtocol
    private let authService: any AuthServiceProtocol
    private let messageService: any MessageServiceProtocol
    private let participantService = ConversationParticipantService.shared
    private let muteService = ConversationMuteService.shared

    init(
        conversationId: UUID,
        participants: [Profile],
        conversationService: any ConversationServiceProtocol = ConversationService.shared,
        profileService: any ProfileServiceProtocol = ProfileService.shared,
        authService: any AuthServiceProtocol = AuthService.shared,
        messageService: any MessageServiceProtocol = MessageService.shared
    ) {
        self.conversationId = conversationId
        self.participants = participants
        self.conversationService = conversationService
        self.profileService = profileService
        self.authService = authService
        self.messageService = messageService
    }

    // MARK: - Initial State

    /// Active participant count, mute state and read-receipt preference (what the popup's `.task` loaded)
    func loadInitialState() async {
        activeParticipantCount = (try? await participantService.fetchActiveParticipantCount(conversationId: conversationId)) ?? 0

        if let userId = authService.currentUserId {
            isConversationMuted = await muteService.isMuted(
                conversationId: conversationId,
                userId: userId
            )

            // Load read receipt preference
            if let showReadReceipts = try? await participantService.fetchShowReadReceipts(
                conversationId: conversationId,
                userId: userId
            ) {
                showReadReceiptsForConversation = showReadReceipts
            }
        }
    }

    // MARK: - Mute

    func mute(duration: ConversationMuteService.MuteDuration) async {
        guard let userId = authService.currentUserId else { return }
        try? await muteService.muteConversation(
            conversationId: conversationId,
            userId: userId,
            duration: duration
        )
        isConversationMuted = true
    }

    func unmute() async {
        guard let userId = authService.currentUserId else { return }
        try? await muteService.unmuteConversation(
            conversationId: conversationId,
            userId: userId
        )
        isConversationMuted = false
    }

    // MARK: - Read Receipts

    func updateShowReadReceipts(_ enabled: Bool) async {
        guard let userId = authService.currentUserId else { return }
        try? await participantService.updateShowReadReceipts(
            conversationId: conversationId,
            userId: userId,
            enabled: enabled
        )
    }

    // MARK: - Save

    /// Upload the new group image (if any) and save the title if it changed.
    /// - Returns: true on success (caller dismisses); on failure `error` is set
    func saveChanges(groupImage: UIImage?, editedTitle: String, currentTitle: String?) async -> Bool {
        isSaving = true
        error = nil
        
        guard let userId = authService.currentUserId else {
            error = "messaging_not_authenticated".localized
            isSaving = false
            return false
        }
        
        var didSave = false
        do {
            // Upload new group image if selected
            if let newImage = groupImage, let imageData = newImage.jpegData(compressionQuality: 0.8) {
                isUploadingImage = true
                let imageUrl = try await conversationService.uploadGroupImage(
                    imageData: imageData,
                    conversationId: conversationId
                )
                try await conversationService.updateGroupImage(
                    conversationId: conversationId,
                    imageUrl: imageUrl,
                    userId: userId
                )
                isUploadingImage = false
            }
            
            // Update title if changed
            let titleToSave = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = titleToSave.isEmpty ? nil : titleToSave
            
            if finalTitle != currentTitle {
                try await conversationService.updateConversationTitle(
                    conversationId: conversationId,
                    title: finalTitle,
                    userId: userId
                )
            }
            
            // Post notification to refresh conversations list
            NotificationCenter.default.post(name: .conversationUpdated, object: conversationId)
            
            didSave = true
        } catch {
            self.error = error.localizedDescription
        }
        
        isSaving = false
        isUploadingImage = false
        return didSave
    }

    // MARK: - Participants

    func addParticipants(_ userIds: [UUID]) async {
        guard let currentUserId = authService.currentUserId else { return }
        
        do {
            AppLogger.info("messaging", "[MessageDetailsPopup] Adding \(userIds.count) participant(s) to conversation \(conversationId)")
            
            try await participantService.addParticipantsToConversation(
                conversationId: conversationId,
                userIds: userIds,
                addedBy: currentUserId,
                createAnnouncement: true
            )
            
            AppLogger.info("messaging", "[MessageDetailsPopup] Successfully added participants, reloading list")
            await loadParticipants()
        } catch {
            AppLogger.error("messaging", "[MessageDetailsPopup] Failed to add participants: \(error.localizedDescription)")
            // The participants INSERT policy admits the conversation's creator only (42501 for
            // everyone else); say so instead of showing the raw row-level-security text.
            if (error as? PostgrestError)?.code == "42501"
                || error.localizedDescription.localizedCaseInsensitiveContains("row-level security") {
                self.error = "messaging_add_participants_creator_only".localized
            } else {
                self.error = "\("messaging_failed_to_add_participants".localized): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Block

    /// Seed `blockedUserIds` from the locally cached blocked-user set
    func refreshBlockedStatus() {
        blockedUserIds.formUnion(participants.map(\.id).filter { messageService.isBlocked($0) })
    }

    /// Record a block made outside this view model (the report sheet's own "Block this user")
    func markBlocked(_ userId: UUID) {
        blockedUserIds.insert(userId)
    }

    /// Block `userId` (the same `block_user` RPC the report sheet and the public profile use).
    /// - Returns: true on success; on failure `blockError` is set (localized)
    func blockUser(_ userId: UUID) async -> Bool {
        guard let currentUserId = authService.currentUserId else {
            blockError = "messaging_must_be_signed_in_to_block".localized
            return false
        }
        isBlocking = true
        defer { isBlocking = false }
        do {
            try await messageService.blockUser(
                blockerId: currentUserId,
                blockedId: userId,
                reason: "Blocked from conversation details"
            )
            blockedUserIds.insert(userId)
            return true
        } catch {
            blockError = "messaging_unable_to_block_user".localized
            return false
        }
    }

    func loadParticipants() async {
        isLoadingParticipants = true
        defer { isLoadingParticipants = false }
        
        do {
            // Fetch participant user IDs (only active participants - not left)
            let participantIds = try await participantService.fetchActiveParticipantIds(conversationId: conversationId)
            
            // Fetch profiles for each participant (show placeholder for deleted users)
            var profiles: [Profile] = []
            for userId in participantIds {
                if let profile = try? await profileService.fetchProfile(userId: userId) {
                    profiles.append(profile)
                } else {
                    // Deleted user — create a placeholder profile
                    profiles.append(Profile(id: userId, name: "messaging_deleted_user".localized, email: ""))
                }
            }
            
            self.participants = profiles
            // A member added from this sheet may be someone the user blocked earlier.
            refreshBlockedStatus()
            AppLogger.info("messaging", "[MessageDetailsPopup] Reloaded \(profiles.count) active participants")
#if DEBUG
            AppLogger.database.debug("[Membership] [MessageDetailsPopup] loadParticipants returned: \(profiles.map { $0.id }.map(\.uuidString))")
#endif
        } catch {
            AppLogger.error("messaging", "[MessageDetailsPopup] Error loading participants: \(error.localizedDescription)")
#if DEBUG
            AppLogger.database.debug("[Membership] [MessageDetailsPopup] loadParticipants error: \(error)")
#endif
        }
    }

    /// Remove a participant and refetch the list. Caller clears its `participantToRemove` afterwards.
    func removeParticipant(userId: UUID) async {
        guard let currentUserId = authService.currentUserId else { return }
        
        isRemovingParticipant = true
        defer { isRemovingParticipant = false }
        
        do {
            try await participantService.removeParticipantFromConversation(
                conversationId: conversationId,
                userId: userId,
                removedBy: currentUserId,
                createAnnouncement: true
            )
            
            // Refetch from authoritative source so UI and parent stay in sync
            await loadParticipants()
            NotificationCenter.default.post(name: .conversationUpdated, object: conversationId)
            
#if DEBUG
            AppLogger.database.debug("[Membership] [MessageDetailsPopup] After remove: refetched \(self.participants.count) participants")
#endif
            AppLogger.info("messaging", "[MessageDetailsPopup] Successfully removed participant")
        } catch {
            AppLogger.error("messaging", "[MessageDetailsPopup] Failed to remove participant: \(error.localizedDescription)")
            self.error = "\("messaging_failed_to_remove_participant".localized): \(error.localizedDescription)"
        }
    }

    /// Leave the conversation. Returns true on success (caller dismisses).
    func leaveConversation() async -> Bool {
        guard let currentUserId = authService.currentUserId else { return false }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await participantService.leaveConversation(
                conversationId: conversationId,
                userId: currentUserId,
                createAnnouncement: true
            )
#if DEBUG
            AppLogger.database.debug("[Membership] [MessageDetailsPopup] leaveConversation succeeded, dismissing")
#endif
            // Post notification to refresh conversations list
            NotificationCenter.default.post(name: .conversationUpdated, object: conversationId)
            
            return true
        } catch {
            self.error = "\("messaging_failed_to_leave_conversation".localized): \(error.localizedDescription)"
            return false
        }
    }
}
