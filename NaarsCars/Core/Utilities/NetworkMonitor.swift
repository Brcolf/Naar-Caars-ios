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
@MainActor
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
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if !networkMonitor.isConnected {
                    HStack(spacing: Constants.Spacing.sm) {
                        Image(systemName: "wifi.slash")
                            .font(.naarsSubheadline)
                        Text("No Internet Connection")
                            .font(.naarsSubheadline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Constants.Spacing.sm)
                    .background(Color.naarsError.opacity(0.9))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: networkMonitor.isConnected)
    }
}

extension View {
    /// Show a "No Internet" banner when the device is offline
    func offlineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}
