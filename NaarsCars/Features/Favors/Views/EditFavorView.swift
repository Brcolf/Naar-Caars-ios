//
//  EditFavorView.swift
//  NaarsCars
//
//  View for editing an existing favor request
//

import SwiftUI

/// View for editing an existing favor request
struct EditFavorView: View {
    let favor: Favor
    @StateObject private var viewModel = CreateFavorViewModel() // Reuse CreateFavorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    
    init(favor: Favor) {
        self.favor = favor
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Title & Description") {
                    TextField("Title", text: $viewModel.title)
                    TextField("Description (optional)", text: $viewModel.description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Location & Duration") {
                    TextField("Location", text: $viewModel.location)
                    
                    Picker("Duration", selection: $viewModel.duration) {
                        ForEach(FavorDuration.allCases, id: \.self) { duration in
                            Text(duration.displayText).tag(duration)
                        }
                    }
                }
                
                Section("Date & Time") {
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    HStack {
                        Text("Time (optional)")
                        Spacer()
                        TextField("HH:mm", text: $viewModel.time)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Details") {
                    TextField("Requirements (optional)", text: $viewModel.requirements, axis: .vertical)
                        .lineLimit(2...4)
                    
                    TextField("Gift/Compensation (optional)", text: $viewModel.gift)
                }
                
                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.naarsError)
                            .font(.naarsCaption)
                    }
                }
            }
            .navigationTitle("Edit Favor Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                _ = try await FavorService.shared.updateFavor(
                                    id: favor.id,
                                    title: viewModel.title.isEmpty ? nil : viewModel.title,
                                    description: viewModel.description.isEmpty ? nil : viewModel.description,
                                    location: viewModel.location.isEmpty ? nil : viewModel.location,
                                    duration: viewModel.duration,
                                    requirements: viewModel.requirements.isEmpty ? nil : viewModel.requirements,
                                    date: viewModel.date,
                                    time: viewModel.time.isEmpty ? nil : viewModel.time,
                                    gift: viewModel.gift.isEmpty ? nil : viewModel.gift
                                )
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .onAppear {
                // Pre-populate form with existing favor data
                viewModel.title = favor.title
                viewModel.description = favor.description ?? ""
                viewModel.location = favor.location
                viewModel.duration = favor.duration
                viewModel.requirements = favor.requirements ?? ""
                viewModel.date = favor.date
                viewModel.time = favor.time ?? ""
                viewModel.gift = favor.gift ?? ""
            }
        }
    }
}

#Preview {
    EditFavorView(favor: Favor(
        userId: UUID(),
        title: "Help moving",
        location: "123 Main St",
        duration: .coupleHours,
        date: Date(),
        status: .open
    ))
}




