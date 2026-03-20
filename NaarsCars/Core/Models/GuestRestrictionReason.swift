//
//  GuestRestrictionReason.swift
//  NaarsCars
//

import Foundation

/// Contextual reasons shown in the guest sign-in prompt sheet.
enum GuestRestrictionReason {
    case claimRide
    case claimFavor
    case postRide
    case postFavor
    case sendMessage
    case viewMap
    case askQuestion
    case createPost
    case commentOnPost
    case voteOnPost
    case reportContent
    case addParticipants
    case deepLinkSignIn
    case joinCommunity

    var title: String {
        switch self {
        case .claimRide:        return "guest_prompt_title_claim_ride".localized
        case .claimFavor:       return "guest_prompt_title_claim_favor".localized
        case .postRide:         return "guest_prompt_title_post_ride".localized
        case .postFavor:        return "guest_prompt_title_post_favor".localized
        case .sendMessage:      return "guest_prompt_title_send_message".localized
        case .viewMap:          return "guest_prompt_title_view_map".localized
        case .askQuestion:      return "guest_prompt_title_ask_question".localized
        case .createPost:       return "guest_prompt_title_create_post".localized
        case .commentOnPost:    return "guest_prompt_title_comment".localized
        case .voteOnPost:       return "guest_prompt_title_vote".localized
        case .reportContent:    return "guest_prompt_title_report".localized
        case .addParticipants:  return "guest_prompt_title_add_participants".localized
        case .deepLinkSignIn:   return "guest_prompt_title_deep_link_sign_in".localized
        case .joinCommunity:    return "guest_prompt_title_join_community".localized
        }
    }

    var message: String {
        switch self {
        case .claimRide:        return "guest_prompt_message_claim_ride".localized
        case .claimFavor:       return "guest_prompt_message_claim_favor".localized
        case .postRide:         return "guest_prompt_message_post_ride".localized
        case .postFavor:        return "guest_prompt_message_post_favor".localized
        case .sendMessage:      return "guest_prompt_message_send_message".localized
        case .viewMap:          return "guest_prompt_message_view_map".localized
        case .askQuestion:      return "guest_prompt_message_ask_question".localized
        case .createPost:       return "guest_prompt_message_create_post".localized
        case .commentOnPost:    return "guest_prompt_message_comment".localized
        case .voteOnPost:       return "guest_prompt_message_vote".localized
        case .reportContent:    return "guest_prompt_message_report".localized
        case .addParticipants:  return "guest_prompt_message_add_participants".localized
        case .deepLinkSignIn:   return "guest_prompt_message_deep_link_sign_in".localized
        case .joinCommunity:    return "guest_prompt_message_join_community".localized
        }
    }
}
