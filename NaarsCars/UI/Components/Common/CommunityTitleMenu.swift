//
//  CommunityTitleMenu.swift
//  NaarsCars
//

import SwiftUI

/// Adds a navigation title menu (and an optional subtitle) only when `enabled`.
///
/// The modifier always takes one structural path: a `.toolbar` and a `navigationSubtitle` are
/// applied in every state and only their contents change. An `if`/`else` on `enabled` would
/// give `content` a different structural identity per branch, so the moment the membership
/// count crossed one (memberships load after the UI is up) or the Requests subtitle appeared,
/// SwiftUI would destroy and rebuild the whole subtree: `@StateObject` view models recreated
/// (losing a Town Hall push target held while memberships load), scroll position and
/// `@State` lost.
///
/// With `enabled == false` the toolbar holds no `ToolbarTitleMenu` and the subtitle is empty;
/// preview renders of that state, large and inline title, are pixel-identical to a title with
/// neither modifier (no chevron, no subtitle line), so a member of one community sees the
/// screen of the previous build. Do not swap the conditional item for an always-present
/// `toolbarTitleMenu { if enabled { ... } }`: an empty title menu still draws the chevron
/// once the title is inline. Apply it to the same view that carries `.navigationTitle`.
/// Shared by the Community tab and Requests so neither feature imports the other.
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
    }
}

extension View {
    /// Shows `menu` as the navigation title menu only when `enabled` (more than one active membership).
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
