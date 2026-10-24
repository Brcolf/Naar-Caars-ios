//
//  ServiceAreaDraftModel.swift
//  NaarsCars
//
//  A listed community's service area while it is being chosen: the town or ZIP code typed, the
//  place it resolved to, the radius, and the nearby check (`check_community_area`) with the reason
//  an overlap needs. Used by the create flow and by the owner's access screen.
//

internal import Combine
import Foundation

@MainActor
final class ServiceAreaDraftModel: ObservableObject {
    /// The town or ZIP code as typed. An edit drops the resolved place and the nearby check.
    @Published var placeQuery: String {
        didSet {
            guard placeQuery != oldValue else { return }
            resolveGeneration += 1
            isResolving = false
            place = nil
            placeError = nil
            invalidateNearbyCheck()
        }
    }

    /// One of `Constants.Community.areaRadiusChoices`. A change needs a new nearby check.
    @Published var radiusMiles: Int {
        didSet {
            guard radiusMiles != oldValue else { return }
            invalidateNearbyCheck()
        }
    }

    @Published private(set) var place: GeocodedPlace?
    @Published private(set) var isResolving = false
    /// Why the typed text gave no place (a street address, or nothing found).
    @Published private(set) var placeError: String?

    /// Listed communities whose area overlaps this one (the server leaves out the default community).
    @Published private(set) var overlaps: [CommunitySearchResult] = []
    @Published private(set) var isCheckingNearby = false
    /// The nearby check answered for the current area.
    @Published private(set) var nearbyChecked = false
    /// The nearby check could not be read; submitting waits for a retry.
    @Published private(set) var nearbyCheckFailed = false

    /// Why a new community is needed where others already serve the area.
    @Published var reason: String = ""

    private let geocoder: any PlaceGeocoding
    private let service: any CommunityServiceProtocol
    /// The community being moved or listed, left out of its own nearby check; nil when creating.
    private let excludedCommunityId: UUID?
    /// A resolve or check that answers after the query, the radius or the area changed is dropped.
    private var resolveGeneration = 0
    private var nearbyGeneration = 0

    init(
        geocoder: any PlaceGeocoding = PlaceGeocoder.shared,
        service: any CommunityServiceProtocol = CommunityService.shared,
        excluding communityId: UUID? = nil,
        initial: ServiceArea? = nil
    ) {
        self.geocoder = geocoder
        self.service = service
        self.excludedCommunityId = communityId
        self.placeQuery = initial?.name ?? ""
        self.radiusMiles = initial?.radiusMiles ?? Constants.Community.defaultAreaRadiusMiles
        self.place = initial.map { GeocodedPlace(label: $0.name, point: $0.center) }
    }

    // MARK: - Derived state

    /// The area to send: the resolved place's label and centre with the chosen radius.
    var area: ServiceArea? {
        place.map { ServiceArea(name: $0.label, center: $0.point, radiusMiles: radiusMiles) }
    }

    /// The nearby check found listed communities serving the area, so a reason is required.
    var needsReason: Bool {
        !overlaps.isEmpty
    }

    var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An area, a finished nearby check, and a reason of 1-300 characters when it found overlaps.
    /// The server checks the overlap again and refuses a missing reason.
    var isReadyToSubmit: Bool {
        guard area != nil, nearbyChecked, !nearbyCheckFailed else { return false }
        guard needsReason else { return true }
        return (1...Constants.Community.listingReasonMaxLength).contains(trimmedReason.count)
    }

    // MARK: - Actions

    /// Starts again from a stored area (or none): the access screen calls it once it has read the
    /// community's settings.
    func reset(to area: ServiceArea?) {
        placeQuery = area?.name ?? ""
        radiusMiles = area?.radiusMiles ?? Constants.Community.defaultAreaRadiusMiles
        resolveGeneration += 1
        isResolving = false
        place = area.map { GeocodedPlace(label: $0.name, point: $0.center) }
        placeError = nil
        invalidateNearbyCheck()
        reason = ""
    }

    /// Resolves the typed text to a town or ZIP code. A street address is refused before any
    /// geocoding, so a centre is never a home; a street-level answer from MapKit reads as not found.
    func resolvePlace() async {
        let query = placeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        resolveGeneration += 1
        let generation = resolveGeneration
        place = nil
        placeError = nil
        invalidateNearbyCheck()

        if PlaceQuery.hasHouseNumber(query) {
            placeError = "community_area_street_refused".localized
            return
        }

        isResolving = true
        let found: GeocodedPlace?
        do {
            found = try await geocoder.resolveTownOrZIP(query)
        } catch is CancellationError {
            if generation == resolveGeneration { isResolving = false }
            return
        } catch {
            // MapKit answers "nothing found" with an error too; the person sees the same sentence.
            found = nil
        }
        guard generation == resolveGeneration else { return }
        isResolving = false
        if let found {
            place = found
        } else {
            placeError = "community_area_not_found".localized
        }
    }

    /// Asks the server which listed communities already serve the area. Nothing to check without
    /// an area. A failure blocks submitting until a retry answers.
    func checkNearby() async {
        guard let area else { return }
        nearbyGeneration += 1
        let generation = nearbyGeneration
        isCheckingNearby = true
        nearbyCheckFailed = false

        do {
            let rows = try await service.checkCommunityArea(area, excluding: excludedCommunityId)
            guard generation == nearbyGeneration else { return }
            overlaps = rows
            nearbyChecked = true
            isCheckingNearby = false
        } catch is CancellationError {
            if generation == nearbyGeneration { isCheckingNearby = false }
        } catch let error as URLError where error.code == .cancelled {
            if generation == nearbyGeneration { isCheckingNearby = false }
        } catch {
            guard generation == nearbyGeneration else { return }
            AppLogger.warning("community", "Nearby community check failed: \(error.localizedDescription)")
            overlaps = []
            nearbyChecked = false
            nearbyCheckFailed = true
            isCheckingNearby = false
        }
    }

    // MARK: - Private

    /// The area changed (or is about to): the last check no longer answers for it.
    private func invalidateNearbyCheck() {
        nearbyGeneration += 1
        isCheckingNearby = false
        nearbyChecked = false
        nearbyCheckFailed = false
        overlaps = []
    }
}
