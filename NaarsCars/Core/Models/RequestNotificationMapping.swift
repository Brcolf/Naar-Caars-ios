import Foundation

enum RequestType: String, Equatable {
    case ride
    case favor
}

enum RequestDetailAnchor: String, Equatable {
    case mainTop
    case statusBadge
    case claimerCard
    case qaSection
    case claimAction
    case completeAction
    case completeSheet
    case reviewSheet
    case claimSheet
    case unclaimSheet

    func anchorId(for requestType: RequestType) -> String {
        let prefix = requestType == .ride ? "requests.rideDetail" : "requests.favorDetail"
        switch self {
        case .mainTop:
            return "\(prefix).mainTop"
        case .statusBadge:
            return "\(prefix).statusBadge"
        case .claimerCard:
            return "\(prefix).claimerCard"
        case .qaSection:
            return "\(prefix).qaSection"
        case .claimAction:
            return "\(prefix).claimAction"
        case .completeAction:
            return "\(prefix).completeAction"
        case .completeSheet:
            return "\(prefix).completeSheet"
        case .reviewSheet:
            return "\(prefix).reviewSheet"
        case .claimSheet:
            return "\(prefix).claimSheet"
        case .unclaimSheet:
            return "\(prefix).unclaimSheet"
        }
    }
}

struct RequestNotificationTarget: Equatable {
    let requestType: RequestType
    let requestId: UUID
    let anchor: RequestDetailAnchor
    let scrollAnchor: RequestDetailAnchor?
    let highlightAnchor: RequestDetailAnchor?
    let shouldAutoClear: Bool
}

enum RequestNotificationMapping {
    static func target(for type: NotificationType, rideId: UUID?, favorId: UUID?) -> RequestNotificationTarget? {
        switch type {
        case .newRide, .rideClaimed, .rideUpdate, .rideCompleted:
            if let rideId {
                return .init(
                    requestType: .ride,
                    requestId: rideId,
                    anchor: .mainTop,
                    scrollAnchor: nil,
                    highlightAnchor: .mainTop,
                    shouldAutoClear: true
                )
            }
        case .newFavor, .favorClaimed, .favorUpdate, .favorCompleted:
            if let favorId {
                return .init(
                    requestType: .favor,
                    requestId: favorId,
                    anchor: .mainTop,
                    scrollAnchor: nil,
                    highlightAnchor: .mainTop,
                    shouldAutoClear: true
                )
            }
        case .rideUnclaimed:
            if let rideId {
                return .init(
                    requestType: .ride,
                    requestId: rideId,
                    anchor: .statusBadge,
                    scrollAnchor: .claimAction,
                    highlightAnchor: .statusBadge,
                    shouldAutoClear: true
                )
            }
        case .favorUnclaimed:
            if let favorId {
                return .init(
                    requestType: .favor,
                    requestId: favorId,
                    anchor: .statusBadge,
                    scrollAnchor: .claimAction,
                    highlightAnchor: .statusBadge,
                    shouldAutoClear: true
                )
            }
        case .completionReminder:
            if let rideId {
                return .init(
                    requestType: .ride,
                    requestId: rideId,
                    anchor: .mainTop,
                    scrollAnchor: nil,
                    highlightAnchor: nil,
                    shouldAutoClear: false
                )
            }
            if let favorId {
                return .init(
                    requestType: .favor,
                    requestId: favorId,
                    anchor: .mainTop,
                    scrollAnchor: nil,
                    highlightAnchor: nil,
                    shouldAutoClear: false
                )
            }
        case .qaActivity, .qaQuestion, .qaAnswer:
            if let rideId {
                return .init(
                    requestType: .ride,
                    requestId: rideId,
                    anchor: .qaSection,
                    scrollAnchor: nil,
                    highlightAnchor: .qaSection,
                    shouldAutoClear: true
                )
            }
            if let favorId {
                return .init(
                    requestType: .favor,
                    requestId: favorId,
                    anchor: .qaSection,
                    scrollAnchor: nil,
                    highlightAnchor: .qaSection,
                    shouldAutoClear: true
                )
            }
        case .reviewRequest, .reviewReminder:
            if let rideId {
                return .init(
                    requestType: .ride,
                    requestId: rideId,
                    anchor: .reviewSheet,
                    scrollAnchor: nil,
                    highlightAnchor: nil,
                    shouldAutoClear: false
                )
            }
            if let favorId {
                return .init(
                    requestType: .favor,
                    requestId: favorId,
                    anchor: .reviewSheet,
                    scrollAnchor: nil,
                    highlightAnchor: nil,
                    shouldAutoClear: false
                )
            }
        default:
            break
        }

        return nil
    }

    static func notificationTypes(for anchor: RequestDetailAnchor, requestType: RequestType) -> [NotificationType] {
        switch anchor {
        case .mainTop:
            switch requestType {
            case .ride:
                return [.newRide, .rideClaimed, .rideUpdate, .rideCompleted]
            case .favor:
                return [.newFavor, .favorClaimed, .favorUpdate, .favorCompleted]
            }
        case .qaSection:
            return [.qaActivity, .qaQuestion, .qaAnswer]
        case .claimAction:
            switch requestType {
            case .ride:
                return [.rideUnclaimed]
            case .favor:
                return [.favorUnclaimed]
            }
        case .completeAction, .completeSheet:
            return [.completionReminder]
        case .reviewSheet:
            return [.reviewRequest, .reviewReminder]
        case .statusBadge, .claimerCard, .claimSheet, .unclaimSheet:
            return []
        }
    }
}


