import Combine
import Foundation

extension ConversationMember {
    static func mock(name: String = "Andrew") -> ConversationMember {
        .init(
            profile: .mock(name: name),
            role: MemberRole.allCases.randomElement() ?? .member,
            isCurrentUser: false
        )
    }

    static func empty(role: MemberRole = .member, isCurrentUser: Bool = false) -> ConversationMember {
        .init(profile: .empty(), role: role, isCurrentUser: isCurrentUser)
    }
}
