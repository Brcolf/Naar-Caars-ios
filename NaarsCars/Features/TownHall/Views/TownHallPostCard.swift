//
//  TownHallPostCard.swift
//  NaarsCars
//
//  Redesigned post-focused card component for Town Hall
//

import SwiftUI

/// Post-focused card component for Town Hall feed
struct TownHallPostCard: View {
    let post: TownHallPost
    let currentUserId: UUID?
    let onDelete: (() -> Void)?
    let onComment: ((UUID) -> Void)? // Post ID
    let onVote: ((UUID, VoteType?) -> Void)? // Post ID, Vote type (nil = remove vote)
    /// Post ID. Called when the comments sheet closes after a comment was added or deleted.
    let onCommentsChanged: ((UUID) -> Void)?
    /// Author ID. Called after the user blocked this post's author from the report sheet.
    let onAuthorBlocked: ((UUID) -> Void)?
    let isHighlighted: Bool
    
    @Environment(AppState.self) private var appState
    @State private var showDeleteAlert = false
    @State private var showComments = false
    @State private var commentsChanged = false
    @State private var showReportSheet = false
    @State private var showGuestPrompt = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasReported = false
    
    init(
        post: TownHallPost,
        currentUserId: UUID?,
        onDelete: (() -> Void)? = nil,
        onComment: ((UUID) -> Void)? = nil,
        onVote: ((UUID, VoteType?) -> Void)? = nil,
        onCommentsChanged: ((UUID) -> Void)? = nil,
        onAuthorBlocked: ((UUID) -> Void)? = nil,
        isHighlighted: Bool = false
    ) {
        self.post = post
        self.currentUserId = currentUserId
        self.onDelete = onDelete
        self.onComment = onComment
        self.onVote = onVote
        self.onCommentsChanged = onCommentsChanged
        self.onAuthorBlocked = onAuthorBlocked
        self.isHighlighted = isHighlighted
    }
    
    var isOwnPost: Bool {
        currentUserId == post.userId
    }

    private var showsHiddenPlaceholder: Bool {
        post.isModerationHidden && isOwnPost
    }

    private var hidesContentCompletely: Bool {
        post.isModerationHidden && !isOwnPost
    }
    
    // Extract title from content (or use provided title)
    private var displayTitle: String {
        if let title = post.title, !title.isEmpty {
            return title
        }
        return PostTitleExtractor.extractTitle(from: post.content)
    }
    
    /// False when the post has no explicit title and the derived title is the entire content,
    /// which would otherwise render the same text twice (title + body).
    private var showsBody: Bool {
        // Posts created in-app store the first line as `title`, so an explicit title can still
        // equal the whole content; compare the rendered title against the content either way.
        displayTitle != post.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isAnnouncement: Bool {
        post.type == .announcement
    }

    private var isReview: Bool {
        post.type == .review
    }

    // Show stars if post is related to a review
    private var starRating: Int? {
        guard isReview, let review = post.review else { return nil }
        return review.rating
    }

    /// The server writes a review post as "⭐⭐⭐⭐⭐ comment". When the card already draws the
    /// rating as its own star row, drop that prefix so the rating is not shown twice.
    private var bodyText: String {
        guard starRating != nil else { return post.content }
        let rest = post.content.drop(while: { $0.isWhitespace || $0.unicodeScalars.first?.value == 0x2B50 })
        return String(rest)
    }

    /// "Brendan reviewed Jane Doe for a ride"
    private var reviewSubtitle: String? {
        guard isReview, let review = post.review else { return nil }
        let authorName = post.author?.name
        let fulfillerName = review.fulfillerName ?? ""

        // Build base: "Author reviewed Fulfiller" or "Reviewed Fulfiller"
        var text: String
        if let authorName {
            text = "townhall_review_by_author".localized(with: authorName, fulfillerName)
        } else {
            text = "townhall_review_anonymous".localized(with: fulfillerName)
        }

        // Append type: "for a ride" or "for a favor"
        if review.rideId != nil {
            text = "townhall_review_for_ride".localized(with: text)
        } else if review.favorId != nil {
            text = "townhall_review_for_favor".localized(with: text)
        }
        return text
    }
    
    var body: some View {
        Group {
            if hidesContentCompletely {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if showsHiddenPlaceholder {
                        hiddenPlaceholderContent
                    } else {
                        regularPostContent
                    }
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(Constants.Radius.card)
                .cardShadow()
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Radius.card)
                        .stroke(
                            isAnnouncement ? Color.naarsPrimary.opacity(0.6) :
                            isHighlighted ? Color.naarsPrimary.opacity(0.6) : Color.clear,
                            lineWidth: (isAnnouncement || isHighlighted) ? 2 : 0
                        )
                )
            }
        }
        .sheet(isPresented: $showComments, onDismiss: {
            // The card's count comes from the feed; without this it stayed at the old number
            // after a comment was deleted until the next pull-to-refresh.
            if commentsChanged {
                commentsChanged = false
                onCommentsChanged?(post.id)
            }
        }) {
            PostCommentsView(postId: post.id, onChanged: { commentsChanged = true })
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentSheet(
                context: .post(
                    id: post.id,
                    authorId: post.userId,
                    preview: post.content.prefix(100) + (post.content.count > 100 ? "..." : "")
                ),
                onReported: { hasReported = true },
                onBlocked: { authorId in onAuthorBlocked?(authorId) }
            )
        }
        .sheet(isPresented: $showGuestPrompt) {
            GuestSignInPromptView(
                reason: .reportContent,
                onSignUp: {
                    appState.isGuestMode = false
                    AppLaunchManager.shared.exitGuestMode()
                },
                onLogIn: {
                    appState.isGuestMode = false
                    AppLaunchManager.shared.exitGuestMode()
                }
            )
        }
        .alert("townhall_delete_post".localized, isPresented: $showDeleteAlert) {
            Button("common_cancel".localized, role: .cancel) { }
            Button("common_delete".localized, role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("townhall_delete_post_confirmation".localized)
        }
    }

    @ViewBuilder
    private var regularPostContent: some View {
        // Title row with star rating (if review-related)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(displayTitle)
                .font(.naarsTitle3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                // When the title is the whole post (single-line posts), it is the only rendering
                // of the text, so it must not be truncated.
                .lineLimit(showsBody ? 2 : nil)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            // Visual star rating for review posts
            if let rating = starRating {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.naarsCaption2)
                            .foregroundColor(star <= rating ? .naarsRating : .secondary.opacity(0.3))
                    }
                }
                // One spoken value instead of five separate star images
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("review_rating_accessibility".localized(with: "\(rating)"))
            }
        }

        // Type badge row
        if isAnnouncement {
            NaarsChip(text: "townhall_badge_announcement".localized, systemImage: "megaphone.fill")
        } else if isReview {
            NaarsChip(text: "townhall_badge_review".localized, systemImage: "star.fill", tint: .naarsWarning)
        }

        authorRow

        // Review subtitle: "Brendan reviewed Jane Doe for a ride"
        if let subtitle = reviewSubtitle {
            Text(subtitle)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .italic()
        }

        Divider()

        // Post content — skipped when the whole content already appears as the derived title
        if showsBody && !bodyText.isEmpty {
            Text(bodyText)
                .font(.naarsBody)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }

        // Image if present
        if let imageUrl = post.imageUrl, !imageUrl.isEmpty {
            CachedAsyncImage(
                url: URL(string: imageUrl),
                placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                },
                errorView: {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .background(Color.naarsInsetBackground)
                        .cornerRadius(Constants.Radius.sm)
                }
            )
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .cornerRadius(Constants.Radius.sm)
        }

        // With no body and no image the divider above already separates the header from the
        // actions; a second one drew an empty band between two rules.
        if showsBody || post.imageUrl?.isEmpty == false {
            Divider()
        }

        actionRow
    }

    @ViewBuilder
    private var hiddenPlaceholderContent: some View {
        authorRow

        Divider()

        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Label("townhall_moderation_hidden_title".localized, systemImage: "eye.slash")
                .font(.naarsHeadline)
                .foregroundColor(.secondary)

            Text("townhall_moderation_hidden_body".localized)
                .font(.naarsBody)
                .foregroundColor(.secondary)

            if let hiddenReason = post.hiddenReason, !hiddenReason.isEmpty {
                Text("moderation_hidden_reason".localized(with: hiddenReason))
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.naarsInsetBackground)
        .cornerRadius(Constants.Radius.sm)

        if isOwnPost, onDelete != nil {
            Divider()

            HStack {
                Spacer()

                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.naarsCaption)
                        .foregroundColor(.naarsError)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("townhall_delete_post".localized)
            }
            .padding(.top, Constants.Spacing.xs)
        }
    }

    @ViewBuilder
    private var authorRow: some View {
        // At accessibility text sizes the name and timestamp no longer fit on one line;
        // stack them instead of breaking words mid-syllable.
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        rowLayout {
            if let author = post.author {
                // The author opens their profile, which has Report and Block.
                NavigationLink(destination: PublicProfileView(userId: post.userId)) {
                    HStack(spacing: 8) {
                        AvatarView(
                            imageUrl: author.avatarUrl,
                            name: author.name,
                            size: 24
                        )
                        Text(author.name)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    // 44-pt tap target around the 24-pt avatar without making the row taller.
                    // Not at accessibility sizes, where the name itself can be taller than that.
                    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 0 : -10)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(author.name)
                .accessibilityHint("townhall_author_profile_hint".localized)
            } else {
                AvatarView(imageUrl: nil, name: "townhall_unknown".localized, size: 24)

                Text("townhall_unknown_user".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !showsHiddenPlaceholder && post.pinned == true {
                Image(systemName: "pin.fill")
                    .font(.naarsCaption2)
                    .foregroundColor(.naarsPrimary)
            }

            Text(post.createdAt.timeAgo)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        // Spacing is 0 because every control carries its own 44-pt tap target (the glyphs are
        // about 12 pt); the frames keep them apart.
        HStack(alignment: .center, spacing: 0) {
            Button(action: {
                showComments = true
                onComment?(post.id)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    if post.commentCount > 0 {
                        Text("\(post.commentCount)")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }
                // Leading-aligned so the glyph stays on the card's text edge
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("townhall_comments".localized)
            .accessibilityValue(String(post.commentCount))

            if !isOwnPost {
                if hasReported {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.naarsCaption)
                        Text("townhall_reported".localized)
                            .font(.naarsCaption)
                    }
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.leading, Constants.Spacing.sm)
                } else {
                    Button(action: {
                        if appState.isGuest {
                            showGuestPrompt = true
                        } else {
                            showReportSheet = true
                        }
                    }) {
                        Image(systemName: "flag")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("townhall_report_post_accessibility".localized)
                }
            }

            Spacer()

            if isOwnPost, onDelete != nil {
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.naarsCaption)
                        .foregroundColor(.naarsError)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("townhall_delete_post".localized)
            }

            HStack(spacing: 8) {
                Button(action: {
                    if post.userVote == .downvote {
                        onVote?(post.id, nil)
                    } else {
                        onVote?(post.id, .downvote)
                    }
                }) {
                    HStack(spacing: Constants.Spacing.xs) {
                        // Filled when it is the user's vote, so the state does not rest on colour alone
                        Image(systemName: post.userVote == .downvote ? "arrowshape.down.fill" : "arrowshape.down")
                            .font(.naarsCaption)
                            .foregroundColor(post.userVote == .downvote ? .naarsPrimary : .secondary)
                        if post.downvotes > 0 {
                            Text("\(post.downvotes)")
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(post.userVote == .downvote ? "townhall_remove_downvote_accessibility".localized : "townhall_downvote_post_accessibility".localized)
                // The explicit label replaces the count text, so say it as the value
                .accessibilityValue(String(post.downvotes))
                .accessibilityHint(post.userVote == .downvote ? "townhall_remove_downvote_hint".localized : "townhall_downvote_post_hint".localized)
                .accessibilityAddTraits(post.userVote == .downvote ? .isSelected : [])

                Button(action: {
                    if post.userVote == .upvote {
                        onVote?(post.id, nil)
                    } else {
                        onVote?(post.id, .upvote)
                    }
                }) {
                    HStack(spacing: Constants.Spacing.xs) {
                        Image(systemName: post.userVote == .upvote ? "arrowshape.up.fill" : "arrowshape.up")
                            .font(.naarsCaption)
                            .foregroundColor(post.userVote == .upvote ? .naarsPrimary : .secondary)
                        if post.upvotes > 0 {
                            Text("\(post.upvotes)")
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(post.userVote == .upvote ? "townhall_remove_upvote_accessibility".localized : "townhall_upvote_post_accessibility".localized)
                .accessibilityValue(String(post.upvotes))
                .accessibilityHint(post.userVote == .upvote ? "townhall_remove_upvote_hint".localized : "townhall_upvote_post_hint".localized)
                .accessibilityAddTraits(post.userVote == .upvote ? .isSelected : [])
            }
        }
        .padding(.top, Constants.Spacing.xs)
    }
}

#Preview {
    let testUserId = UUID()
    let testAuthorId = UUID()
    
    ScrollView {
        VStack(spacing: 16) {
            TownHallPostCard(
                post: TownHallPost(
                    userId: testAuthorId,
                    content: "This is a test post with some content. It can be quite long and will wrap to multiple lines. The title should be extracted from this content automatically.",
                    author: Profile(
                        id: testAuthorId,
                        name: "John Doe",
                        email: "john@example.com",
                        isAdmin: false,
                        approved: true,
                        invitedBy: UUID()
                    ),
                    commentCount: 5,
                    upvotes: 10,
                    downvotes: 2
                ),
                currentUserId: testUserId
            )
            
            TownHallPostCard(
                post: TownHallPost(
                    userId: testAuthorId,
                    content: "Great experience! Highly recommend this service.",
                    type: .review,
                    author: Profile(
                        id: testAuthorId,
                        name: "Jane Smith",
                        email: "jane@example.com",
                        isAdmin: false,
                        approved: true,
                        invitedBy: UUID()
                    ),
                    review: Review(
                        reviewerId: testAuthorId,
                        fulfillerId: UUID(),
                        rating: 5,
                        comment: "Great experience!"
                    ),
                    commentCount: 3,
                    upvotes: 8,
                    downvotes: 0,
                    userVote: .upvote
                ),
                currentUserId: testUserId
            )
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

