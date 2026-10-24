//
//  CreateCommunityViewModel.swift
//  NaarsCars
//
//  Start a community in steps: basics, who can join (listed or hidden, ask to join or invite only),
//  and, for a listed community, its service area and the nearby check. Creates it through
//  create_community_with_area.
//

internal import Combine
import Foundation

/// The steps of Start a community. A hidden community stops after `.access`; the invite step that
/// follows a create is counted in `CreateCommunityViewModel.totalSteps` but is not one of these.
enum CreateCommunityStep: Int, CaseIterable {
    case basics = 1
    case access
    case area
    case nearby

    var title: String {
        switch self {
        case .basics: return "community_create_step_basics".localized
        case .access: return "community_create_step_access".localized
        case .area: return "community_create_step_area".localized
        case .nearby: return "community_create_step_nearby".localized
        }
    }
}

@MainActor
final class CreateCommunityViewModel: ObservableObject {
    @Published var name = ""
    @Published var description = ""
    /// Listed communities appear in search by town or ZIP code and need a service area.
    @Published var isListed = true
    /// New communities default to manual approval; Open is not offered here.
    @Published var joinPolicy: CommunityJoinPolicy = .approve
    @Published private(set) var step: CreateCommunityStep = .basics
    @Published private(set) var isSubmitting = false
    /// True while Next resolves the place or runs the nearby check.
    @Published private(set) var isAdvancing = false
    @Published var errorMessage: String?
    /// The last refusal from the server; the limit-request flow reads `.code == .ownedLimit`.
    @Published private(set) var lastRefusal: CommunityRPCError?

    /// The service area and the nearby check of a listed community. Its changes do not redraw a
    /// view observing only this model; the step bar observes both.
    let areaDraft: ServiceAreaDraftModel

    let policyChoices: [CommunityJoinPolicy] = [.approve, .invite]

    private let service: any CommunityServiceProtocol
    /// The new community starts in the device's time zone; the form shows no field for it (the
    /// owner changes it in Settings).
    private let deviceTimeZone: () -> TimeZone

    init(
        service: any CommunityServiceProtocol = CommunityService.shared,
        geocoder: any PlaceGeocoding = PlaceGeocoder.shared,
        deviceTimeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.service = service
        self.deviceTimeZone = deviceTimeZone
        self.areaDraft = ServiceAreaDraftModel(geocoder: geocoder, service: service)
    }

    // MARK: - Steps

    /// Every step the person sees, the invite step after Create included: 5 listed, 3 hidden.
    var totalSteps: Int {
        isListed ? 5 : 3
    }

    /// "Step N of M · <step>".
    var stepLine: String {
        String(format: "community_create_step".localized, step.rawValue, totalSteps, step.title)
    }

    /// The step whose button reads Create: `.access` for a hidden community, `.nearby` for a listed one.
    var isFinalStep: Bool {
        step == (isListed ? .nearby : .access)
    }

    /// Next (or Create, on the final step) can be tapped.
    var canAdvance: Bool {
        guard !isSubmitting, !isAdvancing else { return false }
        switch step {
        case .basics:
            return basicsAreValid
        case .access:
            return policyChoices.contains(joinPolicy)
        case .area:
            if areaDraft.area != nil { return true }
            // Next resolves a typed town or ZIP code the person did not look up with Find.
            return !trimmedPlaceQuery.isEmpty && !areaDraft.isResolving && areaDraft.placeError == nil
        case .nearby:
            return areaDraft.isReadyToSubmit
        }
    }

    /// The final step waits for a reason: the nearby check found communities serving the area.
    var needsReasonToCreate: Bool {
        isListed && step == .nearby && areaDraft.nearbyChecked && areaDraft.needsReason
            && !areaDraft.isReadyToSubmit
    }

    func next() async {
        guard !isFinalStep, canAdvance else { return }
        switch step {
        case .basics:
            step = .access
        case .access:
            step = .area
        case .area:
            isAdvancing = true
            defer { isAdvancing = false }
            if areaDraft.area == nil {
                await areaDraft.resolvePlace()
                guard areaDraft.area != nil else { return }
            }
            await areaDraft.checkNearby()
            step = .nearby
        case .nearby:
            break
        }
    }

    #if DEBUG
    /// Previews only: shows a step without walking the flow.
    func debugShowStep(_ step: CreateCommunityStep) {
        self.step = step
    }
    #endif

    func back() {
        guard !isSubmitting, !isAdvancing,
              let previous = CreateCommunityStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: - Create

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPlaceQuery: String {
        areaDraft.placeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var basicsAreValid: Bool {
        Constants.Community.nameLength.contains(trimmedName.count)
            && trimmedDescription.count <= Constants.Community.descriptionMaxLength
    }

    /// Creates the community. A listed draft needs an area that passed the nearby check (with a
    /// reason when it found overlaps); the server checks both again.
    func submit() async -> CreatedCommunity? {
        guard !isSubmitting, !isAdvancing, basicsAreValid, policyChoices.contains(joinPolicy) else { return nil }
        let area = isListed ? areaDraft.area : nil
        if isListed {
            guard area != nil, areaDraft.isReadyToSubmit else { return nil }
        }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        lastRefusal = nil

        let cleanName = Validators.sanitizeUserInput(name, maxLength: Constants.Community.nameLength.upperBound)
        let cleanDescription = Validators.sanitizeUserInput(description, maxLength: Constants.Community.descriptionMaxLength)
        let reason = isListed && areaDraft.needsReason ? areaDraft.trimmedReason : nil

        do {
            return try await service.createCommunity(NewCommunityDraft(
                name: cleanName,
                description: cleanDescription.isEmpty ? nil : cleanDescription,
                joinPolicy: joinPolicy,
                timezone: deviceTimeZone().identifier,
                area: area,
                reason: reason
            ))
        } catch let refusal as CommunityRPCError {
            lastRefusal = refusal
            errorMessage = refusal.localizedMessage
            await returnToStep(for: refusal)
            return nil
        } catch {
            AppLogger.error("community", "createCommunity failed: \(error.localizedDescription)")
            errorMessage = "community_error_generic".localized
            return nil
        }
    }

    /// An overlap the client's check missed (`reason_required`) shows the nearby step again with a
    /// fresh check; an area the server refuses (`invalid_area`) goes back to the area step, and the
    /// check runs again for the area shown.
    private func returnToStep(for refusal: CommunityRPCError) async {
        guard isListed else { return }
        switch refusal.code {
        case .reasonRequired:
            step = .nearby
            await areaDraft.checkNearby()
        case .invalidArea:
            step = .area
            await areaDraft.checkNearby()
        default:
            break
        }
    }
}
