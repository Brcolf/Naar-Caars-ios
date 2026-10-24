//
//  OwnedLimitRequestSheet.swift
//  NaarsCars
//
//  Request a higher owned-community limit
//

import SwiftUI

struct OwnedLimitRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: OwnedLimitRequestViewModel
    private let onSent: () -> Void

    @MainActor init(
        currentMax: Int,
        service: any CommunityServiceProtocol = CommunityService.shared,
        onSent: @escaping () -> Void
    ) {
        self.onSent = onSent
        _viewModel = StateObject(wrappedValue: OwnedLimitRequestViewModel(currentMax: currentMax, service: service))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    limitStepper
                } header: {
                    Text("community_limit_request_title".localized)
                        .textCase(nil)
                }

                Section {
                    TextField(
                        "community_limit_request_reason".localized,
                        text: $viewModel.reason,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .accessibilityLabel("community_limit_request_reason".localized)
                    .accessibilityIdentifier("community.limit.reason")
                } footer: {
                    Text("\(viewModel.reason.count)/\(Constants.Community.answerMaxLength)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.naarsBackground)
            .navigationTitle("community_limit_request_title_short".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized) { dismiss() }
                        .disabled(viewModel.isSubmitting)
                        .accessibilityIdentifier("community.limit.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Button("community_limit_request_submit".localized) { submit() }
                            .disabled(!viewModel.canSubmit)
                            .accessibilityIdentifier("community.limit.submit")
                    }
                }
            }
            .errorBanner(message: $viewModel.errorMessage)
            .interactiveDismissDisabled(viewModel.isSubmitting)
        }
    }

    @ViewBuilder
    private var limitStepper: some View {
        let label = String(format: "community_limit_request_number".localized, viewModel.requested)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                Text(label)
                Stepper(label, value: $viewModel.requested, in: viewModel.range)
                    .labelsHidden()
                    .accessibilityLabel(label)
            }
            .accessibilityIdentifier("community.limit.number")
        } else {
            Stepper(label, value: $viewModel.requested, in: viewModel.range)
                .accessibilityIdentifier("community.limit.number")
        }
    }

    private func submit() {
        Task { @MainActor in
            guard await viewModel.submit() else { return }
            onSent()
            dismiss()
        }
    }
}

#if DEBUG
#Preview("Limit 3") {
    OwnedLimitRequestSheet(currentMax: 3, service: PreviewCommunityService(), onSent: {})
}

#Preview("Limit 19") {
    OwnedLimitRequestSheet(currentMax: 19, service: PreviewCommunityService(), onSent: {})
}
#endif
