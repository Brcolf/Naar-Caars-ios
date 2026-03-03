//
//  SavingsSheet.swift
//  NaarsCars
//
//  Sheet showing user's savings breakdown by period
//

import SwiftUI

struct SavingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod = "month"
    @State private var periods: [UserSavingsPeriod] = []
    @State private var isLoading = false
    @State private var error: String?

    private let profileService: any ProfileServiceProtocol = ProfileService.shared

    private var total: Double {
        periods.reduce(0) { $0 + $1.totalSavings }
    }

    private var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: total)) ?? "$0"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("savings_period_label".localized, selection: $selectedPeriod) {
                    Text("period_month".localized).tag("month")
                    Text("period_year".localized).tag("year")
                    Text("period_all_time".localized).tag("all")
                }
                .pickerStyle(.segmented)
                .padding()

                VStack(spacing: 4) {
                    Text(formattedTotal)
                        .font(.system(size: 48, weight: .bold))
                    Text("savings_total_label".localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let error {
                    Spacer()
                    Text(error)
                        .foregroundColor(.secondary)
                    Spacer()
                } else if periods.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "dollarsign.circle.fill",
                        title: "savings_empty_title".localized,
                        message: "savings_empty_message".localized
                    )
                    Spacer()
                } else {
                    List(periods) { period in
                        HStack {
                            Text(period.periodLabel)
                                .font(.naarsBody)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatCurrency(period.totalSavings))
                                    .font(.naarsHeadline)
                                Text("savings_ride_count".localized(with: period.rideCount))
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("savings_nav_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common_done".localized) { dismiss() }
                }
            }
        }
        .task { await loadData() }
        .onChange(of: selectedPeriod) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            periods = try await profileService.fetchUserSavingsBreakdown(period: selectedPeriod)
        } catch {
            self.error = "savings_load_error".localized
            AppLogger.error("profile", "Savings sheet error: \(error.localizedDescription)")
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}
