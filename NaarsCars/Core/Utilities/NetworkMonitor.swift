//
//  NetworkMonitor.swift
//  NaarsCars
//
//  Monitors network connectivity and provides a SwiftUI view modifier
//

import SwiftUI
import Network
internal import Combine

/// Monitors network connectivity status
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published private(set) var isConnected = true
    @Published private(set) var connectionType: NWInterface.InterfaceType?
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.naarscars.networkmonitor")
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}

/// View modifier that shows "No Internet" banner when offline
struct OfflineBannerModifier: ViewModifier {
    @StateObject private var networkMonitor = NetworkMonitor.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if !networkMonitor.isConnected {
                    offlineNotice
                        .padding(.horizontal, Constants.Spacing.md)
                        .padding(.top, Constants.Spacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.naarsStandard, value: networkMonitor.isConnected)
            .onChange(of: networkMonitor.isConnected) { _, isConnected in
                // The notice coming and going is silent for VoiceOver users otherwise.
                AccessibilityAnnouncer.announce(
                    isConnected ? "network_connection_restored".localized : "network_no_connection".localized
                )
            }
    }

    private var offlineNotice: some View {
        HStack(spacing: Constants.Spacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.naarsSubheadline)
                .foregroundColor(.naarsError)
                .accessibilityHidden(true)
            Text("network_no_connection".localized)
                .font(.naarsSubheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Constants.Spacing.md)
        .padding(.vertical, 10)
        // Same shape as the toast: a capsule at one or two lines, a rounded box once large
        // text wraps further, so the glass never cuts into the message.
        .glassEffect(.regular, in: .rect(cornerRadius: Constants.Radius.button))
        .accessibilityElement(children: .combine)
        // Display only. The notice sits over the navigation bar row for as long as the device
        // is offline, so taps must go through to the title and toolbar buttons underneath.
        .allowsHitTesting(false)
    }
}

extension View {
    /// Show a "No Internet" banner when the device is offline
    func offlineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}
