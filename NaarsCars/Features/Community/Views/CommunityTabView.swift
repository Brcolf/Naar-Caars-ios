//
//  CommunityTabView.swift
//  NaarsCars
//
//  The Town Hall tab: one community's feed, with the community's name as a title menu
//

import SwiftUI

/// The Town Hall tab. It hosts the feed only; the leaderboard lives on the community's page.
///
/// The title is the shown community's name (`nav_tab_town_hall` for a guest, or before the
/// memberships load). For a member of any number of communities the title opens a menu: the
/// communities with their unread counts, "About this community" and "Find communities".
struct CommunityTabView: View {
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @State private var communityContext = CommunityContext.shared
    @State private var badgeManager = BadgeCountManager.shared
    @Environment(AppState.self) private var appState
    /// The community page opened from the title menu. Item-driven, never a value-based link.
    @State private var aboutCommunityId: UUID?

    var body: some View {
        NavigationStack {
            TownHallFeedView()
                .navigationTitle(navigationTitleText)
                // A guest has no memberships and no menu: the title is the tab's name.
                .communityTitleMenu(enabled: titleMenuEnabled) {
                    ForEach(communityContext.activeMemberships) { membership in
                        let isSelected = membership.communityId == communityContext.communityTabId
                        let unreadCount = badgeManager.counts.communityUnreadById[membership.communityId] ?? 0
                        Button {
                            communityContext.communityTabId = membership.communityId
                        } label: {
                            if isSelected {
                                Label(membership.name, systemImage: "checkmark")
                            } else {
                                // Menu buttons show a second Text as the row's subtitle.
                                Text(membership.name)
                                if unreadCount > 0 {
                                    Text("community_menu_unread_count".localized(with: unreadCount))
                                }
                            }
                        }
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                    Divider()
                    Button {
                        aboutCommunityId = communityContext.communityTabId
                    } label: {
                        Label("community_menu_about".localized, systemImage: "info.circle")
                    }
                    .disabled(communityContext.communityTabId == nil)
                    .accessibilityIdentifier("townHall.titleMenu.about")
                    Button {
                        // Explore at its root, not on the screen last pushed there.
                        navigationCoordinator.pendingIntent = MyCommunitiesView.findCommunitiesIntent
                    } label: {
                        Label("community_menu_find".localized, systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("townHall.titleMenu.find")
                }
                .navigationDestination(item: $aboutCommunityId) { communityId in
                    // The same identity rule as Explore: another community in place needs a fresh view model.
                    CommunityPageView(communityId: communityId)
                        .id(communityId)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        BellButton {
                            navigationCoordinator.pendingIntent = .notifications
                            AppLogger.info("community", "Bell tapped")
                        }
                    }
                }
                // Arriving on the tab (a tap or a routed push) clears the visible community's badge in
                // MainTabView's onChange(selectedTab). A second clear here in .onAppear ran beside it
                // on every visit (two get_badge_counts calls) and again on every pop back to this root.
                // The tab and the community are observed together so that a switch that changes both
                // in one update (the community page's Town Hall row) is seen as one change.
                .onChange(of: TownHallSelection(
                    tab: navigationCoordinator.selectedTab,
                    communityId: communityContext.communityTabId
                )) { old, new in
                    guard old.communityId != new.communityId else { return }
                    if let newCommunityId = new.communityId {
                        aboutCommunityId = Self.aboutTargetAfterSwitch(
                            current: aboutCommunityId,
                            newCommunity: newCommunityId
                        )
                    }
                    // Switching communities marks the newly visible one read. A change while the
                    // tab is not on screen (a membership refresh) marks nothing read.
                    guard new.tab == .townHall,
                          Self.shouldClearBadge(tabChanged: old.tab != new.tab, communityChanged: true) else { return }
                    Task {
                        await BadgeCountManager.shared.clearCommunityBadge(visibleCommunityId: new.communityId)
                    }
                }
                .onChange(of: navigationCoordinator.pendingIntent) { _, intent in
                    // The feed underneath opens a Town Hall target; leave the community page first.
                    if case .townHallPost = intent {
                        aboutCommunityId = nil
                    }
                }
                .trackScreen("Community")
        }
    }

    // MARK: - Community switch

    /// The tab and its community, observed as one value.
    private struct TownHallSelection: Equatable {
        let tab: NavigationCoordinator.Tab
        let communityId: UUID?
    }

    /// Whether a change of the Town Hall community clears its badge here. A switch that also
    /// selected the tab in the same update is cleared by MainTabView's tab change (the single
    /// tab-change clear), so clearing here as well would read the badge counts twice.
    static func shouldClearBadge(tabChanged: Bool, communityChanged: Bool) -> Bool {
        communityChanged && !tabChanged
    }

    /// The "About this community" page left open after the tab switched to `newCommunity`: a page
    /// of another community closes, so the switch shows that community's feed; the same community
    /// keeps its page.
    static func aboutTargetAfterSwitch(current: UUID?, newCommunity: UUID) -> UUID? {
        guard let current, current == newCommunity else { return nil }
        return current
    }

    /// The menu is for any member, however many communities they belong to. A guest browses the
    /// default community and has no memberships.
    private var titleMenuEnabled: Bool {
        !appState.isGuest && !communityContext.activeMemberships.isEmpty
    }

    /// The Town Hall community's name; `nav_tab_town_hall` for a guest or before the memberships load.
    private var navigationTitleText: String {
        guard titleMenuEnabled,
              let name = communityContext.name(for: communityContext.communityTabId) else {
            return "nav_tab_town_hall".localized
        }
        return name
    }
}

#if DEBUG
#Preview("Member of two communities") {
    let rows = PreviewCommunityService.sampleMemberships
    let _ = CommunityContext.shared.debugSetMemberships(rows)
    let _ = CommunityContext.shared.communityTabId = rows[1].communityId
    CommunityTabView()
        .environment(AppState())
}

#Preview("Guest") {
    let _ = CommunityContext.shared.debugSetMemberships([])
    let guest = AppState()
    let _ = guest.isGuestMode = true
    CommunityTabView()
        .environment(guest)
}
#endif
