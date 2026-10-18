//
//  CommunityTitleMenu.swift
//  NaarsCars
//

import SwiftUI

/// Adds a navigation title menu (and an optional subtitle) only when `enabled`.
///
/// With `enabled == false` the content is returned unchanged: no `toolbarTitleMenu` and no
/// `navigationSubtitle`, so a member of one community sees exactly the view tree of the
/// previous build (no title chevron, no reserved subtitle line). Apply it to the same view
/// that carries `.navigationTitle`. Shared by the Community tab and Requests so neither
/// feature imports the other.
struct CommunityTitleMenuModifier<MenuContent: View>: ViewModifier {
    let enabled: Bool
    let subtitle: String?
    @ViewBuilder let menu: () -> MenuContent

    func body(content: Content) -> some View {
        if enabled, let subtitle {
            content
                .toolbarTitleMenu { menu() }
                .navigationSubtitle(subtitle)
        } else if enabled {
            content
                .toolbarTitleMenu { menu() }
        } else {
            content
        }
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
