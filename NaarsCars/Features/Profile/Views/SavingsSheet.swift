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
                Picker("Period", selection: $selectedPeriod) {
                    Text("Month").tag("month")
                    Text("Year").tag("year")
                    Text("All Time").tag("all")
                }
                .pickerStyle(.segmented)
                .padding()

                VStack(spacing: 4) {
                    Text(formattedTotal)
                        .font(.system(size: 48, weight: .bold))
                    Text("Total Savings")
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
                        title: "No Savings Yet",
                        message: "Savings from shared rides will appear here."
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
                                Text("\(period.rideCount) rides")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("My Savings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
            self.error = "Failed to load savings"
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
