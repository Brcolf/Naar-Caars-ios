//
//  CommunitySearchResultsView.swift
//  NaarsCars
//
//  Explore search results (by name, near a place), the Use my location button, and the search
//  panel other screens put in their own content
//

import SwiftUI

/// The results of an Explore search, drawn over My communities while the field holds a search.
/// The presenter pushes the community page from `onSelect` and opens Create (or the guest's
/// sign-in prompt) from `onStartCommunity`.
struct CommunitySearchResultsView: View {
    @ObservedObject var viewModel: ExploreSearchViewModel
    let isGuest: Bool
    /// The person's membership of a community, for the chip on its row.
    let membership: (UUID) -> CommunityMembership?
    let onSelect: (UUID) -> Void
    let onStartCommunity: () -> Void

    /// The empty-results sentence. Pure, for tests.
    static func emptyText(isGuest: Bool) -> String {
        (isGuest ? "explore_no_results_guest" : "explore_no_results_member").localized
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                UseMyLocationButton(isLocating: viewModel.isLocating) {
                    Task { await viewModel.useMyLocation() }
                }
                .cardStyle()

                CommunitySearchResultsContent(
                    phase: viewModel.phase,
                    results: viewModel.results,
                    isGuest: isGuest,
                    membership: membership,
                    onSelect: onSelect,
                    onStartCommunity: onStartCommunity,
                    onRetry: { Task { await viewModel.retry() } }
                )
            }
            .padding(.horizontal, Constants.Spacing.md)
            .padding(.vertical, Constants.Spacing.sm)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color.naarsBackground)
    }
}

/// A search field with, when `showsUseMyLocation`, the Use my location button above the same
/// results as Explore's. For screens that hold it in their own scrolling content (Get started,
/// Join another community). `isEnabled` false disables row selection.
struct CommunitySearchPanel: View {
    @ObservedObject var viewModel: ExploreSearchViewModel
    let isGuest: Bool
    var isEnabled: Bool = true
    /// Use my location is offered in Explore only (spec 3), so the screens outside it pass false.
    let showsUseMyLocation: Bool
    let membership: (UUID) -> CommunityMembership?
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.md) {
            searchField
            if showsUseMyLocation {
                UseMyLocationButton(isLocating: viewModel.isLocating) {
                    Task { await viewModel.useMyLocation() }
                }
                .cardStyle()
            }
            if viewModel.showsResults {
                CommunitySearchResultsContent(
                    phase: viewModel.phase,
                    results: viewModel.results,
                    isGuest: isGuest,
                    isEnabled: isEnabled,
                    membership: membership,
                    onSelect: onSelect,
                    onStartCommunity: nil,
                    onRetry: { Task { await viewModel.retry() } }
                )
            }
        }
        .toast(message: $viewModel.locationNotice, style: .info)
    }

    private var searchField: some View {
        HStack(spacing: Constants.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.naarsTextSecondary)
                .accessibilityHidden(true)
            TextField("explore_search_prompt".localized, text: $viewModel.query)
                .font(.naarsBody)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("explore_search_prompt".localized)
                .accessibilityIdentifier("community.search.field")
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.naarsTextSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("messaging_search_clear_accessibility".localized)
            }
        }
        .padding(.horizontal, Constants.Spacing.md)
        .frame(minHeight: 44)
        .cardSurface()
    }
}

/// "Use my location", with a spinner while the one fix is awaited. No card of its own: the caller
/// puts it in a list row or a card.
struct UseMyLocationButton: View {
    let isLocating: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Constants.Spacing.md) {
                if isLocating {
                    ProgressView()
                        .frame(minWidth: 28)
                        .accessibilityHidden(true)
                } else if !dynamicTypeSize.isAccessibilitySize {
                    // At accessibility sizes the icon would leave the text a few words per line.
                    Image(systemName: "location.fill")
                        .font(.naarsTitle3)
                        .foregroundColor(.naarsPrimary)
                        .frame(minWidth: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text("explore_use_my_location".localized)
                        .font(.naarsBody)
                        .foregroundColor(.naarsPrimary)
                    Text("explore_use_my_location_hint".localized)
                        .font(.naarsFootnote)
                        .foregroundColor(.naarsTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocating)
        .accessibilityLabel("explore_use_my_location".localized)
        .accessibilityHint("explore_use_my_location_hint".localized)
        .accessibilityIdentifier("explore.search.useMyLocation")
    }
}

/// The groups of a search: loading, failed with Retry, empty, or By name then Near <place>.
/// Shared by `CommunitySearchResultsView` and `CommunitySearchPanel`.
struct CommunitySearchResultsContent: View {
    let phase: ExploreSearchPhase
    let results: ExploreSearchResults
    let isGuest: Bool
    var isEnabled: Bool = true
    let membership: (UUID) -> CommunityMembership?
    let onSelect: (UUID) -> Void
    /// nil: the empty state has no button (the host screen offers its own Start a community).
    let onStartCommunity: (() -> Void)?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.md) {
            switch phase {
            case .idle:
                EmptyView()
            case .failed:
                failedCard
            case .searching where results.isEmpty:
                ForEach(0..<2, id: \.self) { _ in skeletonCard }
            case .searching, .results:
                if phase == .searching {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                if results.isEmpty {
                    emptyCard
                } else {
                    groups
                }
            }
        }
    }

    @ViewBuilder
    private var groups: some View {
        if !results.byName.isEmpty {
            group(title: "explore_group_by_name".localized, footer: nil, rows: results.byName)
        }
        // A town that did not resolve leaves the near group empty; it is not drawn.
        if !results.near.isEmpty {
            group(title: results.nearTitle, footer: "explore_group_near_footer".localized, rows: results.near)
        }
        Text("explore_listed_footer".localized)
            .font(.naarsFootnote)
            .foregroundColor(.naarsTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func group(title: String, footer: String?, rows: [CommunitySearchResult]) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Text(title)
                .font(.naarsHeadline)
                .foregroundColor(.naarsTextPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { result in
                Button {
                    onSelect(result.id)
                } label: {
                    CommunitySearchRow(result: result, membership: membership)
                        .cardStyle()
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityIdentifier("explore.search.row")
            }
            if let footer {
                Text(footer)
                    .font(.naarsFootnote)
                    .foregroundColor(.naarsTextSecondary)
            }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.md) {
            Text(CommunitySearchResultsView.emptyText(isGuest: isGuest))
                .font(.naarsBody)
                .foregroundColor(.naarsTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onStartCommunity {
                // A guest's button opens the sign-in prompt for starting a community.
                PrimaryButton(
                    title: (isGuest ? "guest_prompt_sign_up" : "explore_start_community").localized,
                    action: onStartCommunity
                )
                .accessibilityIdentifier("explore.search.startCommunity")
            }
        }
        .cardStyle()
    }

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Label("explore_search_failed".localized, systemImage: "exclamationmark.triangle.fill")
                .font(.naarsSubheadline)
                .foregroundColor(.naarsTextSecondary)
            SecondaryButton(title: "common_retry".localized, action: onRetry)
                .accessibilityIdentifier("explore.search.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var skeletonCard: some View {
        HStack(spacing: Constants.Spacing.md) {
            SkeletonRectangle(width: 40, height: 40, cornerRadius: 20)
            VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                SkeletonRectangle(width: 180, height: 16)
                SkeletonRectangle(width: 120, height: 12)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
        .accessibilityHidden(true)
    }
}

/// One community of a search: monogram, name, area · distance · members, the join policy and,
/// when the person belongs to it or is waiting, a neutral membership chip.
struct CommunitySearchRow: View {
    let result: CommunitySearchResult
    let membership: (UUID) -> CommunityMembership?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private static let baseMonogramSize: CGFloat = 40
    private static let maxMonogramSize: CGFloat = 64
    @ScaledMetric(relativeTo: .headline) private var scaledMonogramSize: CGFloat = CommunitySearchRow.baseMonogramSize

    /// "Harbor · 0.4 mi · 214 members": the area, the distance and the member count, each left out
    /// when unknown (a name search has no distance). Pure, for tests.
    static func detailText(for result: CommunitySearchResult) -> String {
        var parts: [String] = []
        if let area = result.areaName?.trimmingCharacters(in: .whitespacesAndNewlines), !area.isEmpty {
            parts.append(area)
        }
        if let distance = result.distanceMiles {
            let miles = distance.formatted(.number.precision(.fractionLength(0...1)))
            parts.append(String(format: "explore_distance_miles".localized, miles))
        }
        parts.append(String(
            format: (result.memberCount == 1 ? "community_member_count_one" : "community_member_count_other").localized,
            result.memberCount
        ))
        return parts.dropFirst().reduce(parts[0]) { String(format: "explore_row_detail".localized, $0, $1) }
    }

    /// The membership chip's text; nil when the person has left, was removed, or never joined.
    static func membershipText(_ membership: CommunityMembership?) -> String? {
        guard let membership else { return nil }
        switch membership.status {
        case .pending:
            return "explore_membership_pending".localized
        case .active:
            switch membership.role {
            case .owner: return "explore_membership_owner".localized
            case .admin: return "explore_membership_admin".localized
            case .member: return "explore_membership_member".localized
            }
        case .left, .removed:
            return nil
        }
    }

    var body: some View {
        let detail = Self.detailText(for: result)
        let memberText = Self.membershipText(membership(result.id))
        rowLayout {
            CommunityMonogram(name: result.name, size: min(scaledMonogramSize, Self.maxMonogramSize))
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text(result.name)
                    .font(.naarsHeadline)
                    .foregroundColor(.naarsTextPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.naarsFootnote)
                    .foregroundColor(.naarsTextSecondary)
                    .multilineTextAlignment(.leading)
                if result.policy != nil || memberText != nil {
                    chipLayout {
                        if let policy = result.policy {
                            CommunityPolicyChip(policy: policy)
                        }
                        if let memberText {
                            NaarsChip(text: memberText, tint: nil)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.naarsCaption)
                    .foregroundColor(.naarsTextSecondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ([result.name, detail] + [result.policy?.chipText, memberText].compactMap { $0 }).joined(separator: ", ")
        )
    }

    /// Monogram, text and chevron in a line; stacked at accessibility text sizes.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Constants.Spacing.md))
    }

    /// The chips side by side; stacked at accessibility text sizes, where two do not fit a line.
    private var chipLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Constants.Spacing.xs))
    }
}

#if DEBUG
private enum SearchPreviewData {
    /// The results view after `query` is searched with the preview service and stub geocoder.
    @MainActor
    static func results(
        query: String,
        searchResults: [CommunitySearchResult] = PreviewCommunityService.sampleSearchResults,
        place: GeocodedPlace? = PreviewPlaceGeocoder.seattle,
        isGuest: Bool = false
    ) -> some View {
        let service = PreviewCommunityService()
        service.searchResults = searchResults
        let viewModel = ExploreSearchViewModel(
            service: service,
            geocoder: PreviewPlaceGeocoder(result: place),
            locator: PreviewLocator(),
            debounce: .zero
        )
        let owned = searchResults.first?.id
        return CommunitySearchResultsView(
            viewModel: viewModel,
            isGuest: isGuest,
            membership: { id in
                id == owned ? PreviewCommunityService.membership(name: "Ballard Neighbors", role: .owner) : nil
            },
            onSelect: { _ in },
            onStartCommunity: {}
        )
        .task { await viewModel.search(query) }
    }
}

#Preview("Two groups") {
    SearchPreviewData.results(
        query: "Ballard",
        place: GeocodedPlace(label: "Ballard", point: GeoPoint(latitude: 47.669, longitude: -122.385))
    )
}

#Preview("Empty, guest") {
    SearchPreviewData.results(query: "Wenatchee", searchResults: [], isGuest: true)
}

#Preview("Empty, member") {
    SearchPreviewData.results(query: "Wenatchee", searchResults: [])
}

// The preview service never fails, so the failed state is drawn from the shared content directly.
#Preview("Failed") {
    ScrollView {
        CommunitySearchResultsContent(
            phase: .failed,
            results: ExploreSearchResults(),
            isGuest: false,
            membership: { _ in nil },
            onSelect: { _ in },
            onStartCommunity: {},
            onRetry: {}
        )
        .padding(.horizontal, Constants.Spacing.md)
    }
    .background(Color.naarsBackground)
}
#endif
