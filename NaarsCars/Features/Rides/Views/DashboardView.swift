//
//  DashboardView.swift
//  NaarsCars
//
//  Dashboard view showing ride and favor requests (placeholder)
//

import SwiftUI

/// Dashboard view - placeholder for ride and favor requests
struct DashboardView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Dashboard")
                    .font(.title)
                    .padding()
                
                Text("Ride and favor requests will appear here")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Requests")
        }
    }
}

#Preview {
    DashboardView()
}

