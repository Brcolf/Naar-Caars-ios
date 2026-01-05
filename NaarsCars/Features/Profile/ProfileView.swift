//
//  ProfileView.swift
//  NaarsCars
//
//  Profile view (placeholder)
//

import SwiftUI

/// Profile view - placeholder for user profile
struct ProfileView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Profile")
                    .font(.title)
                    .padding()
                
                Text("Your profile will appear here")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
}

