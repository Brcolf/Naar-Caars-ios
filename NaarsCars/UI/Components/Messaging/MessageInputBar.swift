//
//  MessageInputBar.swift
//  NaarsCars
//
//  Chat input bar component
//

import SwiftUI
import PhotosUI
import AVFoundation
import CoreLocation
import MapKit
internal import Combine

/// Chat input bar component with rich media support
struct MessageInputBar: View {
    @Binding var text: String
    @Binding var imageToSend: UIImage?
    let onSend: () -> Void
    let onImagePickerTapped: () -> Void
    let isDisabled: Bool
    
    /// Reply context (optional - when replying to a message)
    var replyingTo: ReplyContext?
    var onCancelReply: (() -> Void)?
    
    /// Editing context (optional — when editing a message)
    var editingMessage: Message?
    var onCancelEdit: (() -> Void)?
    
    /// Audio message callback
    var onAudioRecorded: ((URL, Double) -> Void)?
    
    /// Location message callback
    var onLocationShare: ((Double, Double, String?) -> Void)?
    
    /// Typing status callback (fired when user types)
    var onTypingChanged: (() -> Void)?
    
    // Audio recording state
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingTimer: Timer?
    @State private var recordingURL: URL?
    
    // Location sharing state
    @State private var showLocationPicker = false
    
    // Expanded attachment menu
    @State private var showAttachmentMenu = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Editing banner (if editing a message)
            if let editing = editingMessage {
                editingBanner(message: editing)
            }
            // Reply context banner (if replying)
            else if let replyContext = replyingTo {
                replyBanner(replyContext: replyContext)
            }
            
            // Audio recording banner
            if isRecording {
                audioRecordingBanner
            }
            
            // Image preview (if image is selected)
            if let image = imageToSend {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .cornerRadius(8)
                    
                    Button(action: { imageToSend = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .background(Color.white.clipShape(Circle()))
                    }
                    .offset(x: -20, y: -40)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
            // Input row
            HStack(spacing: 10) {
                // Attachment button (expands to show options)
                Menu {
                    Button(action: onImagePickerTapped) {
                        Label("Photo", systemImage: "photo.on.rectangle.angled")
                    }
                    
                    Button(action: shareCurrentLocation) {
                        Label("Location", systemImage: "location.fill")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.naarsPrimary)
                }
                
                // Audio record button
                Button(action: toggleRecording) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundColor(isRecording ? .red : .naarsPrimary)
                }
                
                TextField("Type a message...", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit {
                        if !isDisabled {
                            onSend()
                        }
                    }
                    .onChange(of: text) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onTypingChanged?()
                        }
                    }
                    .accessibilityIdentifier("message.input")
                    .accessibilityLabel("Message")
                    .accessibilityHint("Type your message here")
                
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(isDisabled ? .gray : .naarsPrimary)
                }
                .disabled(isDisabled)
                .accessibilityIdentifier("message.send")
            }
            .padding()
        }
        .background(Color.naarsBackgroundSecondary)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: -2)
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerSheet { coordinate, name in
                onLocationShare?(coordinate.latitude, coordinate.longitude, name)
            }
        }
    }
    
    // MARK: - Audio Recording Banner
    
    private var audioRecordingBanner: some View {
        HStack(spacing: 12) {
            // Recording indicator
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(recordingDuration.truncatingRemainder(dividingBy: 1.0) < 0.5 ? 1.0 : 0.3)
            
            Text("messaging_recording".localized)
                .font(.naarsSubheadline).fontWeight(.medium)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Duration
            Text(formatDuration(recordingDuration))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.red)
            
            // Cancel button
            Button(action: cancelRecording) {
                Text("Cancel")
                    .font(.naarsSubheadline).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            // Send button
            Button(action: stopAndSendRecording) {
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
    
    // MARK: - Audio Recording
    
    private func toggleRecording() {
        if isRecording {
            stopAndSendRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        // Request microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    beginRecording()
                }
            }
        }
    }
    
    private func beginRecording() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            // Create temp URL for recording
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "audio_\(UUID().uuidString).m4a"
            let url = tempDir.appendingPathComponent(fileName)
            recordingURL = url
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            
            withAnimation {
                isRecording = true
                recordingDuration = 0
            }
            
            // Start duration timer
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingDuration += 0.1
            }
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
        } catch {
            AppLogger.error("messaging", "Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func stopAndSendRecording() {
        guard let recorder = audioRecorder, let url = recordingURL else { return }
        
        recorder.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        let duration = recordingDuration
        
        withAnimation {
            isRecording = false
        }
        
        // Only send if recording is at least 1 second
        if duration >= 1.0 {
            onAudioRecorded?(url, duration)
        }
        
        // Clean up
        audioRecorder = nil
        recordingURL = nil
        recordingDuration = 0
    }
    
    private func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder?.deleteRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        withAnimation {
            isRecording = false
        }
        
        audioRecorder = nil
        recordingURL = nil
        recordingDuration = 0
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", mins, secs, tenths)
    }
    
    // MARK: - Editing Banner
    
    private func editingBanner(message: Message) -> some View {
        HStack(spacing: 10) {
            // Vertical accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.naarsPrimary)
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                // "Editing" header
                HStack(spacing: Constants.Spacing.xs) {
                    Image(systemName: "pencil")
                        .font(.naarsCaption)
                        .foregroundColor(.naarsPrimary)
                    Text("messaging_editing_message".localized)
                        .font(.naarsFootnote).fontWeight(.semibold)
                        .foregroundColor(.naarsPrimary)
                }
                
                // Original message preview
                Text(message.text)
                    .font(.naarsFootnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Cancel button
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    onCancelEdit?()
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
    
    // MARK: - Location Sharing
    
    private func shareCurrentLocation() {
        showLocationPicker = true
    }
    
    // MARK: - Reply Banner
    
    private func replyBanner(replyContext: ReplyContext) -> some View {
        HStack(spacing: 10) {
            // Vertical accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.naarsPrimary)
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                // "Replying to" header
                HStack(spacing: Constants.Spacing.xs) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.naarsCaption)
                        .foregroundColor(.naarsPrimary)
                    Text("\("messaging_replying_to".localized) \(replyContext.senderName)")
                        .font(.naarsFootnote).fontWeight(.semibold)
                        .foregroundColor(.naarsPrimary)
                }
                
                // Message preview
                HStack(spacing: Constants.Spacing.xs) {
                    if replyContext.imageUrl != nil {
                        Image(systemName: "photo")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                    Text(replyContext.text.isEmpty ? "Photo" : replyContext.text)
                        .font(.naarsFootnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Cancel button
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    onCancelReply?()
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

private struct LocationPickerSheet: View {
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
                TextField("Search for a location", text: $searchText)
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
                            Annotation("Selected", coordinate: coordinate) {
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
                    Text("Send Location")
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
            .navigationTitle("Share Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
private final class LocationPickerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
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

#Preview("Empty Input") {
    MessageInputBar(
        text: .constant(""),
        imageToSend: .constant(nil),
        onSend: {},
        onImagePickerTapped: {},
        isDisabled: true
    )
}

#Preview("With Reply Context") {
    MessageInputBar(
        text: .constant(""),
        imageToSend: .constant(nil),
        onSend: {},
        onImagePickerTapped: {},
        isDisabled: false,
        replyingTo: ReplyContext(
            id: UUID(),
            text: "Hey, can you pick me up at 3pm?",
            senderName: "John Doe",
            senderId: UUID()
        ),
        onCancelReply: {}
    )
}

#Preview("With Text") {
    MessageInputBar(
        text: .constant("Sure, I'll be there!"),
        imageToSend: .constant(nil),
        onSend: {},
        onImagePickerTapped: {},
        isDisabled: false
    )
}

