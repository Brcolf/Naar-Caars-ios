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
    
    @State private var showCopiedToast = false
    @Environment(\.openURL) private var openURL
    
    init(
        _ address: String,
        font: Font = .naarsBody,
        foregroundColor: Color = .primary
    ) {
        self.address = address
        self.font = font
        self.foregroundColor = foregroundColor
    }
    
    var body: some View {
        Text(address)
            .font(font)
            .foregroundColor(foregroundColor)
            .contextMenu {
                // Copy Address
                Button {
                    copyAddress()
                } label: {
                    Label("Copy Address", systemImage: "doc.on.doc")
                }
                
                Divider()
                
                // Open in Apple Maps
                Button {
                    openInAppleMaps()
                } label: {
                    Label("Open in Apple Maps", systemImage: "map")
                }
                
                // Open in Google Maps
                Button {
                    openInGoogleMaps()
                } label: {
                    Label("Open in Google Maps", systemImage: "mappin.and.ellipse")
                }
            }
            .overlay(alignment: .top) {
                if showCopiedToast {
                    CopiedToast()
                        .transition(.move(edge: .top).combined(with: .opacity))
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
        // Encode the address for URL
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }
        
        // Try Apple Maps URL scheme first (opens Maps app directly)
        if let mapsURL = URL(string: "maps://?q=\(encodedAddress)") {
            openURL(mapsURL)
        }
    }
    
    private func openInGoogleMaps() {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }
        
        // Try Google Maps app URL scheme first
        let googleMapsAppURL = URL(string: "comgooglemaps://?q=\(encodedAddress)")
        
        // Fallback to Google Maps web URL (works even if app not installed)
        let googleMapsWebURL = URL(string: "https://www.google.com/maps/search/?api=1&query=\(encodedAddress)")
        
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
                .foregroundColor(.white)
            Text("Copied!")
                .font(.naarsCaption)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
        .shadow(radius: 4)
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

