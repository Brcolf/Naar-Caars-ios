//
//  CameraImagePicker.swift
//  NaarsCars
//
//  UIViewControllerRepresentable wrapper for UIImagePickerController camera capture
//

import SwiftUI
import UIKit

/// Presents the device camera for taking a photo.
/// Usage: offer the Camera option only when `CameraImagePicker.isCameraAvailable`, then
/// `.fullScreenCover(isPresented: $showCamera) { CameraImagePicker { image in ... }.ignoresSafeArea() }`
/// (as a page sheet the camera is letterboxed and can be swiped away mid-capture).
struct CameraImagePicker: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    /// False in the Simulator and on devices where the camera is restricted (Screen Time, device
    /// management).
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Setting .camera while it is unavailable raises NSInvalidArgumentException. Callers hide
        // the Camera option then; if one does not, the picker stays on its default source (the
        // photo library) rather than crashing.
        if Self.isCameraAvailable {
            picker.sourceType = .camera
        }
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImageCaptured: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImageCaptured = onImageCaptured
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
