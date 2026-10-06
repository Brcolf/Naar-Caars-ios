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
                    .accessibilityLabel("messaging_remove_photo_accessibility".localized)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Input row
            HStack(spacing: 10) {
                // Attachment menu (iMessage-style + button)
                Menu {
                    // Only where the host can present a camera (the reply thread cannot): an
                    // item that did nothing when chosen is not offered.
                    if controller.onCameraRequested != nil {
                        Button(action: { controller.onCameraRequested?() }) {
                            Label("photo_source_camera".localized, systemImage: "camera.fill")
                        }
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
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(.label), Color(.tertiarySystemFill))
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
                // Same field as the main composer (MessageInputAccessoryView): 20-pt capsule
                // with a hairline border, so the reply thread does not look like another app.
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(.quaternaryLabel), lineWidth: 1)
                )
                .lineLimit(1...5)
                .submitLabel(.return)
                .focused($isTextFieldFocused)
                .accessibilityIdentifier("message.input")
                .accessibilityLabel("messaging_input_label".localized)
                .accessibilityHint("messaging_input_hint".localized)

                VStack(spacing: 2) {
                    // Characters left, shown near the length limit (red and negative when
                    // over it; the send button is then disabled, see `isSendable`).
                    if controller.showsCharacterCount {
                        Text(verbatim: "\(controller.remainingCharacters)")
                            .font(.naarsCaption2)
                            .monospacedDigit()
                            .foregroundColor(controller.isOverCharacterLimit ? .naarsError : .secondary)
                            .accessibilityLabel(
                                InputBarController.characterCountAccessibilityText(remaining: controller.remainingCharacters)
                            )
                            .accessibilityIdentifier("message.characterCount")
                    }

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
            }
            .padding()
        }
        // Edit raises the keyboard in the composer the text was just placed in.
        .onChange(of: controller.isEditing) { _, isEditing in
            if isEditing { isTextFieldFocused = true }
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
            .accessibilityLabel("messaging_send".localized)
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
            .accessibilityLabel("common_cancel".localized)
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
            .accessibilityLabel("common_cancel".localized)
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

                if viewModel.isLocationAccessDenied {
                    locationAccessNotice
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

                    // Brand colour: red is reserved for errors and destructive actions.
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.naarsPrimary)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                        .accessibilityHidden(true)

                    // Back to the member's own position after panning or searching. Not shown
                    // when location access is off; the notice above covers that case.
                    if !viewModel.isLocationAccessDenied {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button(action: recenterOnUserLocation) {
                                    Image(systemName: "location.fill")
                                        .font(.naarsBody)
                                        .foregroundColor(.naarsPrimary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                        .glassEffect(.regular, in: .capsule)
                                }
                                .accessibilityLabel("messaging_location_current_accessibility".localized)
                                .accessibilityIdentifier("locationPicker.currentLocation")
                                // Lifted off the corner: MapKit draws its "Legal" link there
                                // and the attribution has to stay visible and tappable.
                                .padding(.trailing, Constants.Spacing.sm)
                                .padding(.bottom, Constants.Spacing.xl)
                            }
                        }
                    }
                }
                // 300 pt when there is room; gives way on a short screen so the notice above
                // and the Send button below both stay on screen.
                .frame(minHeight: 200, maxHeight: 300)
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

    /// Centres the map on the member's last known position and asks for a fresh fix; the
    /// camera follows a new fix through the `userCoordinate` observer above.
    private func recenterOnUserLocation() {
        if let coordinate = viewModel.userCoordinate {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        }
        viewModel.requestUserLocation()
    }

    /// Shown when location access is denied or restricted. Without it the sheet silently stayed
    /// on its default map position; a place can still be picked by search or by moving the map.
    private var locationAccessNotice: some View {
        HStack(alignment: .top, spacing: Constants.Spacing.sm) {
            Image(systemName: "location.slash.fill")
                .font(.naarsFootnote)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("messaging_location_access_off_message".localized)
                    .font(.naarsFootnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("messaging_open_settings".localized)
                        .font(.naarsFootnote).fontWeight(.semibold)
                        .foregroundColor(.naarsPrimary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("locationPicker.openSettings")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Constants.Spacing.ms)
        .padding(.top, Constants.Spacing.ms)
        .background(Color.naarsInsetBackground)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.md, style: .continuous))
        .padding(.horizontal)
    }
}

@MainActor
final class LocationPickerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var searchResults: [PlacePrediction] = []
    @Published var selectedCoordinate: CLLocationCoordinate2D?
    @Published var selectedName: String?
    @Published var selectedAddress: String?
    @Published var userCoordinate: CLLocationCoordinate2D?
    /// Location access is denied or restricted: the sheet says so and offers Settings.
    @Published var isLocationAccessDenied = false

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
        isLocationAccessDenied = status == .denied || status == .restricted
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
        // Non-fatal. A denial can surface here as well; show the notice for it.
        if (error as? CLError)?.code == .denied {
            isLocationAccessDenied = true
        }
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
