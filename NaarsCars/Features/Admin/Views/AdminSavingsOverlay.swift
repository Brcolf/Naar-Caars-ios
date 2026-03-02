//
//  AdminSavingsOverlay.swift
//  NaarsCars
//
//  Overlay showing savings breakdown by period
//

import SwiftUI

struct AdminSavingsOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod = "month"
    @State private var periods: [SavingsPeriod] = []
    @State private var isLoading = false
    @State private var error: String?

    private let adminService = AdminService.shared

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
                    Text("Week").tag("week")
                    Text("Month").tag("month")
                    Text("Year").tag("year")
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
                } else {
                    List(periods) { period in
                        HStack {
                            Text(periodLabel(period.periodStart))
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
            .navigationTitle("Total Savings")
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
            periods = try await adminService.fetchSavingsBreakdown(period: selectedPeriod)
        } catch {
            self.error = "Failed to load data"
            AppLogger.error("admin", "Savings overlay error: \(error.localizedDescription)")
        }
    }

    private func periodLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedPeriod {
        case "week":
            formatter.dateFormat = "MMM d, yyyy"
            return "Week of \(formatter.string(from: date))"
        case "year":
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        default:
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}
