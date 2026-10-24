//
//  CommunityTitleMenu.swift
//  NaarsCars
//

import SwiftUI

/// Adds a navigation title menu (and an optional subtitle) only when `enabled`.
///
/// On iOS 26 a title menu is drawn (chevron) and tappable only on an inline title; a large title
/// shows no chevron. The Community tab's large title never collapses, and Requests' collapses
/// only once its list is scrolled; a member cannot be expected to scroll to find the switcher.
/// So while `enabled` the modifier switches the title to `.inline`, and otherwise leaves it
/// `.automatic` (the large title of the previous build).
///
/// The caller decides when the menu is worth showing. The Town Hall tab enables it for every
/// member, of one community or several, because the menu also holds "About this community" and
/// "Find communities"; a guest, who has no memberships, gets none.
///
/// The modifier always takes one structural path: a `.toolbar`, a `navigationSubtitle` and a
/// `toolbarTitleDisplayMode` are applied in every state and only their values change. An
/// `if`/`else` on `enabled` would give `content` a different structural identity per branch, so
/// the moment the membership count crossed one (memberships load after the UI is up) SwiftUI
/// would rebuild the whole subtree: `@StateObject` view models recreated, scroll position and
/// `@State` lost.
///
/// With `enabled == false` the toolbar holds no `ToolbarTitleMenu` and the subtitle is empty,
/// so the title shows neither modifier (no chevron, no subtitle).
/// Do not swap the conditional item for an always-present `toolbarTitleMenu { if enabled { ... } }`:
/// an empty title menu still draws the chevron once the title is inline. Apply it to the same
/// view that carries `.navigationTitle`. Shared by the Community tab and Requests so neither
/// feature imports the other.
struct CommunityTitleMenuModifier<MenuContent: View>: ViewModifier {
    let enabled: Bool
    let subtitle: String?
    @ViewBuilder let menu: () -> MenuContent

    func body(content: Content) -> some View {
        content
            .toolbar {
                if enabled {
                    ToolbarTitleMenu { menu() }
                }
            }
            .navigationSubtitle(Text(verbatim: enabled ? (subtitle ?? "") : ""))
            .toolbarTitleDisplayMode(enabled ? .inline : .automatic)
    }
}

extension View {
    /// Shows `menu` as the navigation title menu only when `enabled`.
    func communityTitleMenu<M: View>(
        enabled: Bool,
        subtitle: String? = nil,
        @ViewBuilder menu: @escaping () -> M
    ) -> some View {
        modifier(CommunityTitleMenuModifier(enabled: enabled, subtitle: subtitle, menu: menu))
    }
}

#Preview("One membership") {
    NavigationStack {
        List { Text(verbatim: "Town Hall") }
            .navigationTitle("community_title".localized)
            .communityTitleMenu(enabled: false) {
                Button { } label: { Text(verbatim: "Naar's Cars Seattle") }
            }
    }
}

#Preview("Two memberships") {
    NavigationStack {
        List { Text(verbatim: "Town Hall") }
            .navigationTitle(Text(verbatim: "Naar's Cars Seattle"))
            .communityTitleMenu(enabled: true) {
                Button { } label: { Label(String("Naar's Cars Seattle"), systemImage: "checkmark") }
                    .accessibilityAddTraits(.isSelected)
                Button { } label: { Text(verbatim: "Capitol Hill Neighbors") }
            }
    }
}
