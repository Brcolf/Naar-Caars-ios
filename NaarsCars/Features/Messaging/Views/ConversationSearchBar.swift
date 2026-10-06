//
//  ConversationSearchBar.swift
//  NaarsCars
//
//  Search bar for searching within a conversation with up/down navigation
//

import SwiftUI

/// Search bar for searching within a conversation with up/down navigation
struct ConversationSearchBar: View {
    @Bindable var viewModel: ConversationDetailViewModel
    /// True while the thread is paging older messages in to reach the selected match.
    var isLocatingResult: Bool = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
                
                TextField("messaging_search_in_conversation".localized, text: $viewModel.searchText)
                    .font(.naarsSubheadline)
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .padding(.vertical, 8)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.naarsSubheadline)
                            .foregroundColor(.secondary)
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("messaging_search_clear_accessibility".localized)
                }
            }
            .padding(.horizontal, 10)
            // At least 44 pt tall: the clear button and the result arrows beside the field
            // are full-size targets and the bar keeps one height as they come and go.
            .frame(minHeight: 44)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.md))
            
            // Results count + navigation
            if !viewModel.searchResults.isEmpty {
                // No spacing: each 44-pt button already carries the room around its glyph.
                HStack(spacing: 0) {
                    if isLocatingResult {
                        // The match is older than the loaded messages; they are being fetched.
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.trailing, Constants.Spacing.xs)
                            .accessibilityLabel("common_loading".localized)
                    }

                    Text("\(viewModel.currentSearchIndex + 1)/\(viewModel.searchResults.count)")
                        .font(.naarsFootnote).fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .fixedSize()
                        .accessibilityLabel("messaging_search_result_position_accessibility".localized(
                            with: viewModel.currentSearchIndex + 1, viewModel.searchResults.count
                        ))

                    Button {
                        viewModel.previousSearchResult()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.naarsFootnote).fontWeight(.semibold)
                            .foregroundColor(.naarsPrimary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("messaging_search_previous_accessibility".localized)

                    Button {
                        viewModel.nextSearchResult()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.naarsFootnote).fontWeight(.semibold)
                            .foregroundColor(.naarsPrimary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("messaging_search_next_accessibility".localized)

                    if viewModel.isLoadingOlderSearchResults {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(minWidth: 44, minHeight: 44)
                    } else if viewModel.canLoadOlderSearchResults {
                        Button {
                            viewModel.loadOlderSearchResults()
                        } label: {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.naarsFootnote).fontWeight(.semibold)
                                .foregroundColor(.naarsPrimary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("messages.search.loadOlder")
                        .accessibilityLabel("messaging_search_load_older_accessibility".localized)
                        .accessibilityHint("messaging_search_load_older_hint".localized)
                    }
                }
            } else if viewModel.isSearchingMessages {
                ProgressView()
                    .scaleEffect(0.7)
            } else if !viewModel.searchText.isEmpty {
                Text("messaging_zero_results".localized)
                    .font(.naarsFootnote)
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        // 4 + the 44-pt field: the bar is the height it was before the targets grew.
        .padding(.vertical, 4)
        .background(Color.naarsBackgroundSecondary)
        .onAppear {
            isFocused = true
        }
    }
}
