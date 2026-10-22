//
//  ExploreSearchViewModel.swift
//  NaarsCars
//
//  Explore search: communities by name and near a town, ZIP code or the device location.
//  A query is never logged, and the device coordinate is rounded before it leaves this type.
//

internal import Combine
import Foundation

enum ExploreSearchPhase: Equatable {
    case idle
    case searching
    case results
    case failed
}

/// The two groups of a search. `near` never repeats a community already in `byName`.
struct ExploreSearchResults: Equatable {
    var byName: [CommunitySearchResult] = []
    var near: [CommunitySearchResult] = []
    /// The town or ZIP code the near group is about; nil for the device location with no town found.
    var placeLabel: String?

    var isEmpty: Bool { byName.isEmpty && near.isEmpty }

    var nearTitle: String {
        guard let placeLabel else { return "explore_group_near_you".localized }
        return String(format: "explore_group_near".localized, placeLabel)
    }
}

@MainActor
final class ExploreSearchViewModel: ObservableObject {
    /// The search field. An edit cancels the pending search and schedules a debounced one.
    @Published var query: String = "" {
        didSet {
            guard !isSettingQueryInternally, query != oldValue else { return }
            showsResults = isSearching
            scheduleSearch()
        }
    }
    @Published private(set) var phase: ExploreSearchPhase = .idle
    @Published private(set) var results = ExploreSearchResults()
    /// True once a location search runs or the query reaches `searchMinLength`; false after `clear()`.
    @Published private(set) var showsResults = false
    @Published private(set) var isLocating = false
    /// A short notice when a granted location fix fails; shown by the presenter as an info toast.
    @Published var locationNotice: String?

    /// The trimmed query is long enough for a name search.
    var isSearching: Bool {
        trimmed(query).count >= Constants.Community.searchMinLength
    }

    private enum NearSource {
        case none
        /// Typed text that looks like a town or ZIP code: geocoded, then searched.
        case town(String)
        /// An already rounded device point and the town it resolved to, if any.
        case point(GeoPoint, label: String?)
    }

    private enum LastRequest {
        case text(String)
        case location(GeoPoint, label: String?)
    }

    private let service: any CommunityServiceProtocol
    private let geocoder: any PlaceGeocoding
    private let locator: any OneShotLocating
    private let debounce: Duration

    private var generation = 0
    /// The debounced search; it holds `self` weakly, so a dropped view model ends it at its next await.
    private var pendingSearch: Task<Void, Never>?
    private var isSettingQueryInternally = false
    private var lastRequest: LastRequest?

    init(
        service: any CommunityServiceProtocol = CommunityService.shared,
        geocoder: any PlaceGeocoding = PlaceGeocoder.shared,
        locator: any OneShotLocating = DeviceLocator(),
        debounce: Duration = Constants.Community.searchDebounce
    ) {
        self.service = service
        self.geocoder = geocoder
        self.locator = locator
        self.debounce = debounce
    }

    // MARK: - Search

    /// Searches by name and, when the text looks like a town or ZIP code, near that place.
    /// Only the newest search writes its answer; a cancelled search changes nothing.
    func search(_ text: String) async {
        generation += 1
        let current = generation
        let value = trimmed(text)
        guard value.count >= Constants.Community.searchMinLength else {
            lastRequest = nil
            phase = .idle
            results = ExploreSearchResults()
            showsResults = false
            return
        }
        lastRequest = .text(value)
        showsResults = true
        phase = .searching
        let near: NearSource = PlaceQuery.looksLikeTownOrZIP(value) ? .town(value) : .none
        await run(generation: current, name: value, near: near)
    }

    /// One device fix, rounded, then the communities near it and, when its town is found, by that name.
    /// A refused location makes no call and shows nothing.
    func useMyLocation() async {
        guard locator.access != .denied, !isLocating else { return }
        isLocating = true
        locationNotice = nil
        let fix = await locator.currentLocation(timeout: Constants.Community.locationSearchTimeout)
        guard let fix else {
            // No fix: a typed search that is pending or running goes on and writes its answer.
            isLocating = false
            if locator.access != .denied {
                locationNotice = "explore_location_unavailable".localized
            }
            return
        }
        // Only a fix replaces the typed search; the generation bump below makes its answer win.
        pendingSearch?.cancel()
        let point = fix.rounded(toDecimals: Constants.Community.searchCoordinateDecimals)
        generation += 1
        let current = generation
        showsResults = true
        phase = .searching
        let place: GeocodedPlace?
        do {
            place = try await geocoder.resolveTownOrZIP(at: point)
        } catch {
            if Self.isCancellation(error) {
                isLocating = false
                return
            }
            place = nil
        }
        isLocating = false
        guard current == generation else { return }
        await runLocation(generation: current, point: point, label: place?.label)
    }

    /// Runs the last search again with the same input (a location search does not ask for a new fix).
    func retry() async {
        switch lastRequest {
        case .text(let text):
            await search(text)
        case .location(let point, let label):
            generation += 1
            let current = generation
            phase = .searching
            await runLocation(generation: current, point: point, label: label)
        case nil:
            return
        }
    }

    /// Empties the field and the results and hides the results (the field's clear button or a dismissal).
    func clear() {
        pendingSearch?.cancel()
        pendingSearch = nil
        generation += 1
        setQueryInternally("")
        lastRequest = nil
        phase = .idle
        results = ExploreSearchResults()
        showsResults = false
    }

    // MARK: - Private

    private func scheduleSearch() {
        pendingSearch?.cancel()
        let text = query
        let debounce = debounce
        pendingSearch = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            await self?.search(text)
        }
    }

    private func runLocation(generation current: Int, point: GeoPoint, label: String?) async {
        lastRequest = .location(point, label: label)
        var name: String?
        if let label {
            setQueryInternally(label)
            if trimmed(label).count >= Constants.Community.searchMinLength { name = trimmed(label) }
        }
        await run(generation: current, name: name, near: .point(point, label: label))
    }

    private func run(generation current: Int, name: String?, near: NearSource) async {
        async let nameOutcome = nameSearch(name)
        async let nearOutcome = nearSearch(near)
        let (byName, nearby) = await (nameOutcome, nearOutcome)

        guard current == generation, !Task.isCancelled else { return }
        if byName?.isCancelled == true || nearby?.result.isCancelled == true { return }

        let names = byName?.value
        let nearList = nearby?.result.value
        let attempted = (byName != nil ? 1 : 0) + (nearby != nil ? 1 : 0)
        let failed = (byName?.failed == true ? 1 : 0) + (nearby?.result.failed == true ? 1 : 0)
        guard attempted > 0, failed < attempted else {
            phase = .failed
            results = ExploreSearchResults()
            return
        }

        let nameList = names ?? []
        let nameIds = Set(nameList.map(\.id))
        results = ExploreSearchResults(
            byName: nameList,
            near: (nearList ?? []).filter { !nameIds.contains($0.id) },
            placeLabel: nearby?.label
        )
        phase = .results
    }

    private struct NearOutcome {
        let result: Outcome
        let label: String?
    }

    private enum Outcome {
        case success([CommunitySearchResult])
        case failure(Error)

        var value: [CommunitySearchResult]? {
            if case .success(let list) = self { return list }
            return nil
        }

        var failed: Bool {
            if case .failure(let error) = self { return !ExploreSearchViewModel.isCancellation(error) }
            return false
        }

        var isCancelled: Bool {
            if case .failure(let error) = self { return ExploreSearchViewModel.isCancellation(error) }
            return false
        }
    }

    /// nil when no name search applies.
    private func nameSearch(_ name: String?) async -> Outcome? {
        guard let name else { return nil }
        let text = String(name.prefix(Constants.Community.searchMaxLength))
        do {
            return .success(try await service.searchCommunities(name: text))
        } catch {
            return .failure(error)
        }
    }

    /// nil when no place search applies. A town that does not resolve is an empty group, not a failure.
    private func nearSearch(_ source: NearSource) async -> NearOutcome? {
        switch source {
        case .none:
            return nil
        case .town(let text):
            do {
                guard let place = try await geocoder.resolveTownOrZIP(text) else {
                    return NearOutcome(result: .success([]), label: nil)
                }
                let point = place.point.rounded(toDecimals: Constants.Community.searchCoordinateDecimals)
                let list = try await service.findCommunitiesNear(point)
                return NearOutcome(result: .success(list), label: place.label)
            } catch {
                return NearOutcome(result: .failure(error), label: nil)
            }
        case .point(let point, let label):
            do {
                return NearOutcome(result: .success(try await service.findCommunitiesNear(point)), label: label)
            } catch {
                return NearOutcome(result: .failure(error), label: label)
            }
        }
    }

    private func setQueryInternally(_ value: String) {
        isSettingQueryInternally = true
        query = value
        isSettingQueryInternally = false
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
