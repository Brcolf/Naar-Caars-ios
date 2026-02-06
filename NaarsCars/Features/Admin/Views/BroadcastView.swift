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
    @State private var showSuccess = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("admin_broadcast_title".localized, text: $viewModel.title)
                        .font(.naarsBody)
                    
                    TextEditor(text: $viewModel.message)
                        .frame(minHeight: 150)
                        .font(.naarsBody)
                } header: {
                    Text("admin_announcement".localized)
                } footer: {
                    Text("admin_announcement_footer".localized)
                }
                
                Section {
                    Toggle("admin_pin_toggle".localized, isOn: $viewModel.pinToNotifications)
                        .font(.naarsBody)
                } footer: {
                    Text("admin_pin_footer".localized)
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
                                Text("admin_send_broadcast".localized)
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
                        ? Color.naarsDivider
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
                
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("admin_send_announcement".localized)
            .navigationBarTitleDisplayMode(.inline)
            .alert("admin_send_broadcast".localized, isPresented: $showingConfirmation) {
                Button("common_cancel".localized, role: .cancel) {}
                Button("admin_send".localized, role: .none) {
                    Task {
                        await viewModel.sendBroadcast()
                    }
                }
            } message: {
                Text("admin_broadcast_confirmation".localized)
            }
            .onChange(of: viewModel.successMessage) { _, newValue in
                if newValue != nil {
                    showSuccess = true
                }
            }
        }
        .successCheckmark(isShowing: $showSuccess)
    }
}

#Preview {
    BroadcastView()
}


