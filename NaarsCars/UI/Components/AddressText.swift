//
//  AddressText.swift
//  NaarsCars
//
//  Tappable address text with context menu for copy and open in maps
//

import SwiftUI
import MapKit

/// A text view for addresses that supports long-press context menu
/// with options to copy or open in Apple Maps / Google Maps
struct AddressText: View {
    let address: String
    let font: Font
    let foregroundColor: Color
    let isRedacted: Bool

    @State private var showCopiedToast = false
    @Environment(\.openURL) private var openURL

    init(
        _ address: String,
        font: Font = .naarsBody,
        foregroundColor: Color = .primary,
        isRedacted: Bool = false
    ) {
        self.address = address
        self.font = font
        self.foregroundColor = foregroundColor
        self.isRedacted = isRedacted
    }

    var body: some View {
        if isRedacted {
            // This line stands in for the address on every card a guest sees, so it is reading
            // text, not a placeholder: tertiary measured about 1.7:1 on the card (4.5:1 needed).
            Label {
                Text("guest_address_hidden".localized)
                    .font(font)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "lock.fill")
                    .font(.naarsCaption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("guest_address_hidden_accessibility".localized)
        } else {
            Text(address)
                .font(font)
                .foregroundColor(foregroundColor)
                .contextMenu {
                    // Copy Address
                    Button {
                        copyAddress()
                    } label: {
                        Label("address_copy_action".localized, systemImage: "doc.on.doc")
                    }

                    Divider()

                    // Open in Apple Maps
                    Button {
                        openInAppleMaps()
                    } label: {
                        Label("address_open_apple_maps".localized, systemImage: "map")
                    }

                    // Open in Google Maps
                    Button {
                        openInGoogleMaps()
                    } label: {
                        Label("address_open_google_maps".localized, systemImage: "mappin.and.ellipse")
                    }
                }
                .overlay(alignment: .top) {
                    if showCopiedToast {
                        CopiedToast()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
        }
    }
    
    // MARK: - Actions
    
    private func copyAddress() {
        UIPasteboard.general.string = address
        
        // Show toast feedback
        withAnimation(.spring(response: 0.3)) {
            showCopiedToast = true
        }
        
        // Hide toast after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3)) {
                showCopiedToast = false
            }
        }
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func openInAppleMaps() {
        // Use the 'address' parameter for better geocoding results in Apple Maps
        // The 'q' parameter is for general search, 'address' is more specific.
        // Built from a query item: `.urlQueryAllowed` left "&" unescaped, so
        // "5th Ave & Pine St" opened Maps searching for "5th Ave ".
        if let mapsURL = MapsLaunchCoordinator.makeURL(
            base: "https://maps.apple.com/",
            queryItems: [URLQueryItem(name: "address", value: address)]
        ) {
            openURL(mapsURL)
        }
    }

    private func openInGoogleMaps() {
        // Try Google Maps app URL scheme first
        let googleMapsAppURL = MapsLaunchCoordinator.makeURL(
            base: "comgooglemaps://",
            queryItems: [URLQueryItem(name: "q", value: address)]
        )

        // Fallback to Google Maps web URL (works even if app not installed)
        let googleMapsWebURL = MapsLaunchCoordinator.makeURL(
            base: Constants.URLs.googleMapsSearch,
            queryItems: [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "query", value: address)
            ]
        )

        if let appURL = googleMapsAppURL, UIApplication.shared.canOpenURL(appURL) {
            // Google Maps app is installed - open it
            openURL(appURL)
        } else if let webURL = googleMapsWebURL {
            // Fallback to web URL (opens in browser or in-app browser)
            openURL(webURL)
        }
    }
}

// MARK: - Copied Toast

private struct CopiedToast: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.naarsSuccess)
            Text("address_copied_toast".localized)
                .font(.naarsCaption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AddressText("123 Main Street, Seattle, WA 98101")
        
        AddressText(
            "Pike Place Market, Seattle",
            font: .naarsHeadline,
            foregroundColor: .naarsPrimary
        )
        
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.rideAccent)
            AddressText("Space Needle, 400 Broad St, Seattle, WA")
        }
    }
    .padding()
}


