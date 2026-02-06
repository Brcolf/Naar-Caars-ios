//
//  ConversationSearchBar.swift
//  NaarsCars
//
//  Search bar for searching within a conversation with up/down navigation
//

import SwiftUI

/// Search bar for searching within a conversation with up/down navigation
struct ConversationSearchBar: View {
    @ObservedObject var viewModel: ConversationDetailViewModel
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
                
                TextField("Search in conversation", text: $viewModel.searchText)
                    .font(.naarsSubheadline)
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.naarsSubheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            // Results count + navigation
            if !viewModel.searchResults.isEmpty {
                HStack(spacing: 4) {
                    Text("\(viewModel.currentSearchIndex + 1)/\(viewModel.searchResults.count)")
                        .font(.naarsFootnote).fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .fixedSize()
                    
                    Button {
                        viewModel.previousSearchResult()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.naarsFootnote).fontWeight(.semibold)
                            .foregroundColor(.naarsPrimary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        viewModel.nextSearchResult()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.naarsFootnote).fontWeight(.semibold)
                            .foregroundColor(.naarsPrimary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
        .padding(.vertical, 8)
        .background(Color.naarsBackgroundSecondary)
        .onAppear {
            isFocused = true
        }
    }
}
