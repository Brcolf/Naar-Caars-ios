//
//  ServiceAreaPicker.swift
//  NaarsCars
//
//  The service-area step (a town or ZIP code, a radius and the map), the nearby check that follows
//  it, and the area map the community page also shows. The picker and the check are `Form`
//  sections; the map is a plain inset card with no interaction and no pin.
//

import MapKit
import SwiftUI

/// The service-area step: the town or ZIP code field with Find, the resolved place, the radius and
/// the map of the circle. Place it inside a `Form`.
struct ServiceAreaPicker: View {
    @ObservedObject var model: ServiceAreaDraftModel

    var body: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Constants.Spacing.sm) {
                    queryField
                    findButton
                }
                VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                    queryField
                    findButton
                }
            }
            // The separator under the field runs from the row's edge, not from the Find button.
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            if model.isResolving {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("common_loading".localized)
            } else if let error = model.placeError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsError)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let place = model.place {
                Label(place.label, systemImage: "mappin.and.ellipse")
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Section {
            Picker("community_area_radius_label".localized, selection: $model.radiusMiles) {
                ForEach(Constants.Community.areaRadiusChoices, id: \.self) { miles in
                    Text(Self.radiusText(miles)).tag(miles)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("community.area.radius")
        } header: {
            Text("community_area_radius_label".localized)
        } footer: {
            if model.area == nil {
                footer
            }
        }

        if let area = model.area {
            Section {
                ServiceAreaMap(area: area)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                footer
            }
        }
    }

    /// Under the map once there is one, under the radius before.
    private var footer: some View {
        Text("community_area_footer".localized)
    }

    private var queryField: some View {
        TextField("community_area_field_placeholder".localized, text: $model.placeQuery)
            .textContentType(.addressCityAndState)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit(find)
            .accessibilityLabel("community_area_field_placeholder".localized)
            .accessibilityIdentifier("community.area.query")
    }

    private var findButton: some View {
        Button("community_area_find".localized, action: find)
            .buttonStyle(.bordered)
            .disabled(!canFind)
            .accessibilityLabel("community_area_find".localized)
            .accessibilityIdentifier("community.area.find")
    }

    private var canFind: Bool {
        !model.isResolving && !model.placeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func find() {
        guard canFind else { return }
        Task { await model.resolvePlace() }
    }

    static func radiusText(_ miles: Int) -> String {
        String(format: "community_area_radius_value".localized, miles)
    }
}

/// The nearby check: the listed communities already serving the area, each with View, and the
/// reason a new one needs; or "none", or a failure with Retry. Place it inside a `Form`. It runs
/// the check itself when it appears with an unchecked area (a failure waits for Retry).
struct NearbyCheckSection: View {
    @ObservedObject var model: ServiceAreaDraftModel
    let onView: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if model.isCheckingNearby {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("common_loading".localized)
                }
            } else if model.nearbyCheckFailed {
                Section {
                    Label("community_nearby_failed".localized, systemImage: "exclamationmark.triangle")
                        .font(.naarsSubheadline)
                        .foregroundColor(.naarsTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("common_retry".localized) {
                        Task { await model.checkNearby() }
                    }
                    .accessibilityIdentifier("community.nearby.retry")
                }
            } else if model.needsReason {
                overlapSections
            } else if model.nearbyChecked {
                Section {
                    Label("community_nearby_none".localized, systemImage: "checkmark.circle")
                        .font(.naarsSubheadline)
                        .foregroundColor(.naarsTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: model.area) {
            guard model.area != nil, !model.nearbyChecked, !model.nearbyCheckFailed, !model.isCheckingNearby else { return }
            await model.checkNearby()
        }
    }

    @ViewBuilder
    private var overlapSections: some View {
        Section {
            ForEach(model.overlaps) { community in
                row(community)
            }
        } header: {
            Text(titleText(model.overlaps.count))
        } footer: {
            Text("community_nearby_body".localized)
        }

        Section {
            TextField(
                "community_nearby_reason_placeholder".localized,
                text: $model.reason,
                axis: .vertical
            )
            .lineLimit(3...6)
            .onChange(of: model.reason) { _, newValue in
                if newValue.count > Constants.Community.listingReasonMaxLength {
                    model.reason = String(newValue.prefix(Constants.Community.listingReasonMaxLength))
                }
            }
            .accessibilityLabel("community_nearby_reason_label".localized)
            .accessibilityIdentifier("community.nearby.reason")
        } header: {
            HStack(spacing: Constants.Spacing.sm) {
                Text("community_nearby_reason_label".localized)
                NaarsChip(text: "community_nearby_reason_required".localized, tint: .naarsPrimary)
            }
        } footer: {
            Text("community_nearby_reason_footer".localized
                 + "  \(model.trimmedReason.count)/\(Constants.Community.listingReasonMaxLength)")
        }
    }

    private func row(_ community: CommunitySearchResult) -> some View {
        // View moves under the text once the text is too large to share a line with it.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Constants.Spacing.ms))
        return layout {
            VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                Text(community.name)
                    .font(.naarsHeadline)
                    .foregroundColor(.naarsTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detailText(community))
                    .font(.naarsFootnote)
                    .foregroundColor(.naarsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let policy = community.policy {
                    CommunityPolicyChip(policy: policy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button("community_nearby_view".localized) { onView(community.id) }
                .buttonStyle(.bordered)
                .accessibilityLabel("community_nearby_view".localized + ", " + community.name)
        }
        .accessibilityIdentifier("community.nearby.row")
    }

    private func titleText(_ count: Int) -> String {
        String(format: (count == 1 ? "community_nearby_title_one" : "community_nearby_title_other").localized, count)
    }

    private func detailText(_ community: CommunitySearchResult) -> String {
        let members = String(
            format: (community.memberCount == 1 ? "community_member_count_one" : "community_member_count_other").localized,
            community.memberCount
        )
        guard let areaName = community.areaName else { return members }
        return areaName + " · " + members
    }
}

/// A community's service area on a map: one circle, no pin, no interaction, in a plain inset card.
struct ServiceAreaMap: View {
    let area: ServiceArea

    /// How much wider than the circle the map shows, so its edge is not at the card's edge.
    private static let regionPadding = 1.3

    var body: some View {
        Map(position: .constant(.region(region)), interactionModes: []) {
            MapCircle(center: center, radius: radiusMeters)
                .foregroundStyle(Color.naarsPrimary.opacity(Constants.Community.areaMapFillOpacity))
                .stroke(Color.naarsPrimary, lineWidth: 1)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: Constants.Community.areaMapHeight)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.sm, style: .continuous))
        .allowsHitTesting(false)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.servesText(area))
    }

    private var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: area.center.latitude, longitude: area.center.longitude)
    }

    private var radiusMeters: CLLocationDistance {
        Measurement(value: Double(area.radiusMiles), unit: UnitLength.miles).converted(to: .meters).value
    }

    private var region: MKCoordinateRegion {
        let span = radiusMeters * 2 * Self.regionPadding
        return MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)
    }

    /// "Serves Ballard and about 2 miles around it".
    static func servesText(_ area: ServiceArea) -> String {
        String(
            format: (area.radiusMiles == 1 ? "community_page_serves_one" : "community_page_serves_other").localized,
            area.name, area.radiusMiles
        )
    }
}

#if DEBUG
// MARK: - Previews

private enum ServiceAreaPreviewData {
    /// A draft whose query resolved to Seattle and whose nearby check found two communities.
    @MainActor
    static func resolvedWithOverlaps() -> ServiceAreaDraftModel {
        let service = PreviewCommunityService()
        service.overlappingCommunities = Array(PreviewCommunityService.sampleSearchResults.prefix(2))
        let model = ServiceAreaDraftModel(geocoder: PreviewPlaceGeocoder(), service: service)
        model.placeQuery = "Seattle"
        Task {
            await model.resolvePlace()
            await model.checkNearby()
        }
        return model
    }

    /// A street address typed where a town is expected.
    @MainActor
    static func streetRefused() -> ServiceAreaDraftModel {
        let model = ServiceAreaDraftModel(geocoder: PreviewPlaceGeocoder(), service: PreviewCommunityService())
        model.placeQuery = "5412 Sample Ave NW"
        Task { await model.resolvePlace() }
        return model
    }
}

#Preview("Resolved area with overlaps") {
    let model = ServiceAreaPreviewData.resolvedWithOverlaps()
    return NavigationStack {
        Form {
            ServiceAreaPicker(model: model)
            NearbyCheckSection(model: model, onView: { _ in })
        }
        .scrollContentBackground(.hidden)
        .background(Color.naarsBackground)
    }
}

#Preview("Nearby check with a reason") {
    let model = ServiceAreaPreviewData.resolvedWithOverlaps()
    model.reason = "We want a group just for parents at one school."
    return NavigationStack {
        Form {
            NearbyCheckSection(model: model, onView: { _ in })
        }
        .scrollContentBackground(.hidden)
        .background(Color.naarsBackground)
    }
}

#Preview("Street address refused") {
    let model = ServiceAreaPreviewData.streetRefused()
    return NavigationStack {
        Form {
            ServiceAreaPicker(model: model)
        }
        .scrollContentBackground(.hidden)
        .background(Color.naarsBackground)
    }
}

#Preview("Area map") {
    ScrollView {
        ServiceAreaMap(area: PreviewCommunityService.sampleArea)
            .padding(Constants.Spacing.md)
    }
    .background(Color.naarsBackground)
}
#endif
