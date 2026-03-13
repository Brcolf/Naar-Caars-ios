//
//  MessageInputBar.swift
//  NaarsCars
//
//  Chat input bar component — thin rendering shell over InputBarController
//

import SwiftUI
import CoreLocation
import MapKit
internal import Combine

/// Chat input bar component with rich media support.
/// Reads all state from `InputBarController`; delegates all mutations to it.
struct MessageInputBar: View {
    let controller: InputBarController
    let isDisabled: Bool

    @FocusState private var isTextFieldFocused: Bool
    @State private var sendButtonScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Editing banner (if editing a message)
            if case .editing(_, let originalText) = controller.mode {
                editingBanner(originalText: originalText)
            }
            // Reply context banner (if replying)
            else if case .replying(let replyContext) = controller.mode {
                replyBanner(replyContext: replyContext)
            }

            // Audio recording banner
            if controller.isRecording {
                audioRecordingBanner
            }

            // Image preview (if image is selected)
            if let image = controller.attachmentState.previewImage {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .cornerRadius(8)

                    Button(action: { controller.clearAttachment() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .background(Color(.systemBackground).clipShape(Circle()))
                    }
                    .offset(x: -20, y: -40)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Input row
            HStack(spacing: 10) {
                // Attachment menu (iMessage-style + button)
                Menu {
                    Button(action: { controller.onCameraRequested?() }) {
                        Label("photo_source_camera".localized, systemImage: "camera.fill")
                    }

                    Button(action: { controller.onImagePickerRequested?() }) {
                        Label("messaging_menu_photo".localized, systemImage: "photo.on.rectangle.angled")
                    }

                    Button(action: {
                        if controller.isRecording {
                            controller.stopRecording()
                        } else {
                            controller.startRecording()
                        }
                    }) {
                        Label("messaging_menu_voice_note".localized, systemImage: "mic.fill")
                    }

                    Button(action: { controller.onLocationPickerRequested?() }) {
                        Label("messaging_menu_location".localized, systemImage: "location.fill")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.naarsPrimary)
                }
                .accessibilityLabel("messaging_menu_add".localized)
                .accessibilityHint("messaging_menu_add_hint".localized)

                TextField(
                    controller.isEditing ? "messaging_edit_placeholder".localized : "messaging_placeholder".localized,
                    text: Binding(
                        get: { controller.currentText },
                        set: { controller.updateText($0) }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .submitLabel(.return)
                .focused($isTextFieldFocused)
                .accessibilityIdentifier("message.input")
                .accessibilityLabel("messaging_input_label".localized)
                .accessibilityHint("messaging_input_hint".localized)

                Button(action: {
                    withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                        sendButtonScale = 0.8
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            sendButtonScale = 1.0
                        }
                    }
                    controller.send()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(controller.isSendable && !isDisabled ? .naarsPrimary : .gray)
                }
                .scaleEffect(sendButtonScale)
                .disabled(!controller.isSendable || isDisabled)
                .accessibilityIdentifier("message.send")
                .accessibilityLabel("messaging_send".localized)
                .accessibilityHint("messaging_send_hint".localized)
            }
            .padding()
        }
        .background(Color.naarsBackgroundSecondary)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: -2)
    }

    // MARK: - Audio Recording Banner

    private var audioRecordingBanner: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .modifier(PulsingOpacity())

            Text("messaging_recording".localized)
                .font(.naarsSubheadline).fontWeight(.medium)
                .foregroundColor(.primary)

            Spacer()

            Text(formatDuration(controller.recordingDuration))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.red)

            Button(action: { controller.cancelRecording() }) {
                Text("common_cancel".localized)
                    .font(.naarsSubheadline).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            Button(action: { controller.stopRecording() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(.naarsPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.naarsCardBackground)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", mins, secs, tenths)
    }

    // MARK: - Editing Banner

    private func editingBanner(originalText: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.naarsPrimary)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Constants.Spacing.xs) {
                    Image(systemName: "pencil")
                        .font(.naarsCaption)
                        .foregroundColor(.naarsPrimary)
                    Text("messaging_editing_message".localized)
                        .font(.naarsFootnote).fontWeight(.semibold)
                        .foregroundColor(.naarsPrimary)
                }

                Text(originalText)
                    .font(.naarsFootnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    controller.cancelEditing()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.naarsTitle3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.naarsCardBackground)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Reply Banner

    private func replyBanner(replyContext: ReplyContext) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.naarsPrimary)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Constants.Spacing.xs) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.naarsCaption)
                        .foregroundColor(.naarsPrimary)
                    Text("\("messaging_replying_to".localized) \(replyContext.senderName)")
                        .font(.naarsFootnote).fontWeight(.semibold)
                        .foregroundColor(.naarsPrimary)
                }

                HStack(spacing: Constants.Spacing.xs) {
                    if replyContext.imageUrl != nil {
                        Image(systemName: "photo")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                    Text(replyContext.text.isEmpty ? "messaging_menu_photo".localized : replyContext.text)
                        .font(.naarsFootnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    controller.cancelReply()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.naarsTitle3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.naarsCardBackground)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Location Picker Sheet

struct LocationPickerSheet: View {
    let onSelect: (CLLocationCoordinate2D, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LocationPickerViewModel()
    @State private var searchText = ""
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("messaging_location_search_placeholder".localized, text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .onChange(of: searchText) { _, newValue in
                        Task { await viewModel.search(query: newValue) }
                    }

                if !viewModel.searchResults.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(viewModel.searchResults) { result in
                                Button {
                                    Task {
                                        await viewModel.selectPrediction(result)
                                        if let coordinate = viewModel.selectedCoordinate {
                                            cameraPosition = .region(
                                                MKCoordinateRegion(
                                                    center: coordinate,
                                                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                                                )
                                            )
                                        }
                                        searchText = ""
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                        Text(result.primaryText)
                                            .font(.naarsSubheadline).fontWeight(.semibold)
                                        if !result.secondaryText.isEmpty {
                                            Text(result.secondaryText)
                                                .font(.naarsFootnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal)
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                ZStack {
                    Map(position: $cameraPosition) {
                        if let coordinate = viewModel.selectedCoordinate {
                            Annotation("messaging_location_selected".localized, coordinate: coordinate) {
                                EmptyView()
                            }
                        }
                    }
                    .onMapCameraChange { context in
                        viewModel.updateCoordinateFromMap(context.region.center)
                    }

                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.red)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                VStack(spacing: Constants.Spacing.xs) {
                    if let name = viewModel.selectedName {
                        Text(name)
                            .font(.naarsSubheadline).fontWeight(.semibold)
                    }
                    if let address = viewModel.selectedAddress, !address.isEmpty {
                        Text(address)
                            .font(.naarsFootnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                Button(action: confirmSelection) {
                    Text("messaging_send_location".localized)
                        .font(.naarsCallout).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.naarsPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.selectedCoordinate == nil)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .navigationTitle("messaging_share_location_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.requestUserLocation()
            }
            .onChange(of: viewModel.userCoordinate?.latitude) { _, _ in
                if let coordinate = viewModel.userCoordinate {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        )
                    )
                }
            }
        }
    }

    private func confirmSelection() {
        guard let coordinate = viewModel.selectedCoordinate else { return }
        let name = viewModel.selectedName ?? viewModel.selectedAddress
        onSelect(coordinate, name)
        dismiss()
    }
}

@MainActor
final class LocationPickerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var searchResults: [PlacePrediction] = []
    @Published var selectedCoordinate: CLLocationCoordinate2D?
    @Published var selectedName: String?
    @Published var selectedAddress: String?
    @Published var userCoordinate: CLLocationCoordinate2D?

    private let locationManager = CLLocationManager()
    private let locationService = LocationService.shared
    private let geocoder = CLGeocoder()
    private var reverseGeocodeTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestUserLocation() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        }
    }

    func search(query: String) async {
        guard query.count >= 2 else {
            searchResults = []
            return
        }

        do {
            searchResults = try await locationService.searchPlaces(query: query)
        } catch {
            searchResults = []
        }
    }

    func selectPrediction(_ prediction: PlacePrediction) async {
        do {
            let details = try await locationService.getPlaceDetails(placeID: prediction.placeID)
            selectedCoordinate = details.coordinate
            selectedName = details.name
            selectedAddress = details.address
            searchResults = []
        } catch {
            searchResults = []
        }
    }

    func updateCoordinateFromMap(_ coordinate: CLLocationCoordinate2D) {
        selectedCoordinate = coordinate
        reverseGeocodeTask?.cancel()
        reverseGeocodeTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await reverseGeocode(coordinate: coordinate)
        }
    }

    private func reverseGeocode(coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            let components = [
                placemark.name,
                placemark.thoroughfare,
                placemark.locality
            ].compactMap { $0 }
            selectedName = components.first
            selectedAddress = components.dropFirst().joined(separator: ", ")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestUserLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        userCoordinate = location.coordinate
        selectedCoordinate = location.coordinate
        Task {
            await reverseGeocode(coordinate: location.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal: location permission may be denied
    }
}

// MARK: - Pulsing Opacity (recording indicator)

/// Animates opacity between 1.0 and 0.3 using a repeating SwiftUI animation
/// instead of a high-frequency timer, keeping the main thread free.
private struct PulsingOpacity: ViewModifier {
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

// MARK: - Focus State Helper

private extension View {
    /// Conditionally applies `.focused()` only when a binding is provided
    @ViewBuilder
    func applyFocusState(_ binding: FocusState<Bool>.Binding?) -> some View {
        if let binding = binding {
            self.focused(binding)
        } else {
            self
        }
    }
}
