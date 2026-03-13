//
//  GroupAvatarComposite.swift
//  NaarsCars
//
//  Composite avatar that arranges participant photos in a circular group avatar.
//

import SwiftUI

struct GroupAvatarComposite: View {
    let participants: [Participant]
    var size: CGFloat = 56

    struct Participant: Sendable {
        let imageUrl: String?
        let name: String
    }

    var body: some View {
        Group {
            switch participants.count {
            case 0:
                emptyAvatar
            case 1:
                singleAvatar(participants[0])
            case 2:
                twoAvatarLayout
            case 3:
                threeAvatarLayout
            default:
                fourAvatarGrid
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("Group avatar")
    }

    // MARK: - Layouts

    private var emptyAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.naarsPrimary.opacity(0.2))
            Image(systemName: "person.2.fill")
                .foregroundColor(.naarsPrimary)
                .font(.system(size: size * 0.35))
        }
    }

    private func singleAvatar(_ participant: Participant) -> some View {
        AvatarView(
            imageUrl: participant.imageUrl,
            name: participant.name,
            size: size
        )
    }

    private var twoAvatarLayout: some View {
        HStack(spacing: 0) {
            participantTile(participants[0])
            participantTile(participants[1])
        }
    }

    private var threeAvatarLayout: some View {
        let cellSize = size / 2
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                participantTile(participants[0])
                participantTile(participants[1])
            }
            .frame(height: cellSize)
            participantTile(participants[2])
                .frame(width: cellSize, height: cellSize)
        }
    }

    private var fourAvatarGrid: some View {
        let items = Array(participants.prefix(4))
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                participantTile(items[0])
                participantTile(items[1])
            }
            HStack(spacing: 0) {
                participantTile(items[2])
                participantTile(items[3])
            }
        }
    }

    // MARK: - Tile

    private func participantTile(_ participant: Participant) -> some View {
        Group {
            if let imageUrl = participant.imageUrl, !imageUrl.isEmpty {
                CachedAsyncImage(
                    url: URL(string: imageUrl),
                    placeholder: { initialsView(for: participant) },
                    errorView: { initialsView(for: participant) }
                )
                .aspectRatio(contentMode: .fill)
            } else {
                initialsView(for: participant)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func initialsView(for participant: Participant) -> some View {
        let initials = Self.initials(from: participant.name)
        let fontSize = participants.count == 1 ? size * 0.4 : size * 0.22
        return Text(initials.uppercased())
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.naarsPrimary)
    }

    // MARK: - Helpers

    private static func initials(from name: String) -> String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1)) + String(components[1].prefix(1))
        } else if !components.isEmpty {
            return String(components[0].prefix(2))
        }
        return "??"
    }
}

#Preview {
    VStack(spacing: 20) {
        // 0 participants
        GroupAvatarComposite(participants: [])

        // 1 participant
        GroupAvatarComposite(participants: [
            .init(imageUrl: nil, name: "Alice Adams")
        ])

        // 2 participants
        GroupAvatarComposite(participants: [
            .init(imageUrl: nil, name: "Alice Adams"),
            .init(imageUrl: nil, name: "Bob Baker")
        ])

        // 3 participants
        GroupAvatarComposite(participants: [
            .init(imageUrl: nil, name: "Alice Adams"),
            .init(imageUrl: nil, name: "Bob Baker"),
            .init(imageUrl: nil, name: "Charlie Clark")
        ])

        // 4+ participants
        GroupAvatarComposite(participants: [
            .init(imageUrl: nil, name: "Alice Adams"),
            .init(imageUrl: nil, name: "Bob Baker"),
            .init(imageUrl: nil, name: "Charlie Clark"),
            .init(imageUrl: nil, name: "Diana Davis")
        ], size: 80)
    }
    .padding()
}
