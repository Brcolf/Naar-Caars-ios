//
//  BroadcastView.swift
//  NaarsCars
//
//  View for sending broadcast announcements
//

import SwiftUI

/// View for sending broadcast announcements
struct BroadcastView: View {
    @StateObject private var viewModel = BroadcastViewModel()
    @State private var showingConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $viewModel.title)
                        .font(.naarsBody)
                    
                    TextEditor(text: $viewModel.message)
                        .frame(minHeight: 150)
                        .font(.naarsBody)
                } header: {
                    Text("Announcement")
                } footer: {
                    Text("This will be sent to all approved users.")
                }
                
                Section {
                    Toggle("Pin to notifications (7 days)", isOn: $viewModel.pinToNotifications)
                        .font(.naarsBody)
                } footer: {
                    Text("If enabled, the announcement will appear pinned at the top of users' notification feeds for 7 days.")
                }
                
                Section {
                    Button(action: {
                        showingConfirmation = true
                    }) {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Send Broadcast")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(viewModel.title.isEmpty || viewModel.message.isEmpty || viewModel.isLoading)
                    .foregroundColor(
                        (viewModel.title.isEmpty || viewModel.message.isEmpty || viewModel.isLoading)
                        ? .secondary
                        : .white
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        (viewModel.title.isEmpty || viewModel.message.isEmpty || viewModel.isLoading)
                        ? Color.gray.opacity(0.3)
                        : Color.naarsPrimary
                    )
                    .cornerRadius(8)
                }
                
                if let error = viewModel.error {
                    Section {
                        Text(error.localizedDescription)
                            .font(.naarsCaption)
                            .foregroundColor(.naarsError)
                    }
                }
                
                if let success = viewModel.successMessage {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.naarsSuccess)
                            Text(success)
                                .font(.naarsCaption)
                                .foregroundColor(.naarsSuccess)
                        }
                    }
                }
            }
            .navigationTitle("Send Announcement")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Send Broadcast", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Send", role: .none) {
                    Task {
                        await viewModel.sendBroadcast()
                    }
                }
            } message: {
                Text("This will send an announcement to all approved users. Are you sure you want to proceed?")
            }
        }
    }
}

#Preview {
    BroadcastView()
}


