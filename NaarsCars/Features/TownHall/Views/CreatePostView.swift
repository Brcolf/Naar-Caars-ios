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
    /// Called once a post has been created, before the sheet dismisses.
    var onPosted: (() -> Void)? = nil
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showSuccess = false
    @State private var showCameraPicker = false
    @State private var showPhotoSource = false
    @State private var showPhotoLibrary = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $viewModel.content)
                        .frame(minHeight: 120)
                        .accessibilityLabel("townhall_whats_on_your_mind".localized)
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
                            .accessibilityLabel("townhall_character_count_accessibility".localized(with: viewModel.characterCount, 500))
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
                            .cornerRadius(Constants.Radius.sm)
                        
                        Button("townhall_remove_image".localized, role: .destructive) {
                            viewModel.removeImage()
                            // Otherwise choosing the same photo again is not seen as a change
                            selectedPhotoItem = nil
                        }
                    } header: {
                        Text("townhall_image".localized)
                    }
                } else {
                    Section {
                        Button {
                            // With no camera (Simulator, restricted device) the library is the only
                            // source, so skip the one-option menu.
                            if CameraImagePicker.isCameraAvailable {
                                showPhotoSource = true
                            } else {
                                showPhotoLibrary = true
                            }
                        } label: {
                            Label("townhall_add_photo".localized, systemImage: "photo")
                        }
                    } header: {
                        Text("townhall_image_optional".localized)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // A banner at the top instead of caption text in the last form row, which sat below
            // the keyboard when a post or photo failed.
            .errorBanner(message: Binding(
                get: { viewModel.error?.localizedDescription },
                set: { if $0 == nil { viewModel.error = nil } }
            ))
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
                                onPosted?()
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
        .confirmationDialog("townhall_photo_source".localized, isPresented: $showPhotoSource, titleVisibility: .hidden) {
            Button("photo_source_camera".localized) {
                showCameraPicker = true
            }
            // A dialog takes plain buttons only; a PhotosPicker placed here has no live view to
            // present from once the dialog closes. The picker is attached to the view below.
            Button("photo_source_library".localized) {
                showPhotoLibrary = true
            }
        }
        .photosPicker(
            isPresented: $showPhotoLibrary,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let newItem = newItem {
                    await loadImage(from: newItem)
                }
            }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraImagePicker { image in
                viewModel.selectedImage = image
            }
            .ignoresSafeArea()
        }
    }

    private func loadImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            await MainActor.run {
                // Clear the selection so picking the same photo again is seen as a change
                selectedPhotoItem = nil
                viewModel.error = .invalidInput("profile_image_load_failed".localized)
            }
            return
        }

        await MainActor.run {
            viewModel.error = nil
            viewModel.selectedImage = uiImage
        }
    }
}

#Preview {
    CreatePostView()
}

