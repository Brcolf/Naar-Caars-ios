//
//  AdminFulfilledOverlay.swift
//  NaarsCars
//
//  Overlay showing fulfilled requests breakdown by period
//

import SwiftUI

struct AdminFulfilledOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod = "month"
    @State private var periods: [FulfilledPeriod] = []
    @State private var isLoading = false
    @State private var error: String?

    private let adminService = AdminService.shared

    private var total: Int {
        periods.reduce(0) { $0 + $1.totalCount }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("savings_period_label".localized, selection: $selectedPeriod) {
                    Text("period_week".localized).tag("week")
                    Text("period_month".localized).tag("month")
                    Text("period_year".localized).tag("year")
                }
                .pickerStyle(.segmented)
                .padding()

                VStack(spacing: 4) {
                    Text("\(total)")
                        .font(.system(size: 48, weight: .bold))
                    Text("admin_requests_fulfilled_label".localized)
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
                                Text("\(period.totalCount)")
                                    .font(.naarsHeadline)
                                Text("admin_rides_favors_count".localized(with: period.rideCount, period.favorCount))
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("admin_requests_fulfilled_title".localized)
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
            periods = try await adminService.fetchFulfilledBreakdown(period: selectedPeriod)
        } catch {
            self.error = "common_load_error".localized
            AppLogger.error("admin", "Fulfilled overlay error: \(error.localizedDescription)")
        }
    }

    private func periodLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedPeriod {
        case "week":
            formatter.dateFormat = "MMM d, yyyy"
            return "admin_week_of".localized(with: formatter.string(from: date))
        case "year":
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        default:
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
    }
}
