import SwiftUI
import EventKit

extension Array where Element: EKParticipant {
    /// 참석 상태(수락 → 미정 → 대기 → 거절) 순으로 정렬한다.
    func sortedByStatus() -> [EKParticipant] {
        sorted { a, b in
            let ra = a.statusRank, rb = b.statusRank
            if ra != rb { return ra < rb }
            return (a.name ?? a.url.absoluteString) < (b.name ?? b.url.absoluteString)
        }
    }
}

private extension EKParticipant {
    var statusRank: Int {
        switch participantStatus {
        case .accepted, .completed, .inProcess: return 0
        case .tentative, .delegated:            return 1
        case .pending, .unknown:                return 2
        case .declined:                         return 3
        @unknown default:                       return 2
        }
    }
}

struct ParticipantRow: View {
    let participant: EKParticipant

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIconAndColor.icon)
                .foregroundStyle(statusIconAndColor.color)
                .font(.system(size: 13))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.body)
                    if participant.participantRole == .optional {
                        Text(String(localized: "Optional"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if participant.participantRole == .chair {
                    Text(String(localized: "Organizer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let email = emailAddress, email != displayName {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var displayName: String {
        if let name = participant.name, !name.isEmpty { return name }
        return emailAddress ?? participant.url.absoluteString
    }

    private var emailAddress: String? {
        let urlString = participant.url.absoluteString
        guard urlString.hasPrefix("mailto:") else { return nil }
        let email = String(urlString.dropFirst("mailto:".count))
        return email.isEmpty ? nil : email
    }

    private var statusIconAndColor: (icon: String, color: Color) {
        switch participant.participantStatus {
        case .accepted, .completed, .inProcess:
            return ("checkmark.circle.fill", .green)
        case .declined:
            return ("xmark.circle.fill", .red)
        case .tentative, .delegated:
            return ("questionmark.circle.fill", .orange)
        case .pending, .unknown:
            return ("circle", .secondary)
        @unknown default:
            return ("circle", .secondary)
        }
    }
}
