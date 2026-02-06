//
//  CreatePostView.swift
//  NaarsCars
//
//  View for creating town hall posts
//

import SwiftUI
import PhotosUI

/// View for creating town hall posts
struct CreatePostView: View {
    @StateObject private var viewModel = CreatePostViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $viewModel.content)
                        .frame(minHeight: 120)
                        .onChange(of: viewModel.content) { oldValue, newValue in
                            // Limit to 500 characters (only if actually exceeding limit)
                            if newValue.count > 500 && oldValue.count <= 500 {
                                viewModel.content = String(newValue.prefix(500))
                            }
                        }
                    
                    // Character count
                    HStack {
                        Spacer()
                        Text("\(viewModel.characterCount)/500")
                            .font(.naarsCaption)
                            .foregroundColor(viewModel.characterCount > 500 ? .naarsError : .secondary)
                    }
                } header: {
                    Text("townhall_whats_on_your_mind".localized)
                }
                
                // Image section
                if let image = viewModel.selectedImage {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(8)
                        
                        Button("townhall_remove_image".localized, role: .destructive) {
                            viewModel.removeImage()
                        }
                    } header: {
                        Text("townhall_image".localized)
                    }
                } else {
                    Section {
                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images
                        ) {
                            Label("townhall_add_photo".localized, systemImage: "photo")
                        }
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                if let newItem = newItem {
                                    await loadImage(from: newItem)
                                }
                            }
                        }
                    } header: {
                        Text("townhall_image_optional".localized)
                    }
                }
                
                // Error display
                if let error = viewModel.error {
                    Section {
                        Text(error.localizedDescription)
                            .font(.naarsCaption)
                            .foregroundColor(.naarsError)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("townhall_new_post".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common_cancel".localized) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("townhall_post".localized) {
                        Task {
                            do {
                                _ = try await viewModel.validateAndPost()
                                showSuccess = true
                                HapticManager.success()
                                try? await Task.sleep(nanoseconds: Constants.Timing.successDismissNanoseconds)
                                dismiss()
                            } catch {
                                // Error is handled by viewModel
                            }
                        }
                    }
                    .disabled(!viewModel.canPost)
                    .fontWeight(.semibold)
                }
            }
        }
        .successCheckmark(isShowing: $showSuccess)
    }
    
    private func loadImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            return
        }
        
        await MainActor.run {
            viewModel.selectedImage = uiImage
        }
    }
}

#Preview {
    CreatePostView()
}

