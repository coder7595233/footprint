import AppKit
import Foundation
import SwiftUI

private let groupMailAddressExpression = try! NSRegularExpression(
    pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
    options: [.caseInsensitive]
)

func extractedGroupMailAddresses(from rawValue: String) -> [String] {
    let range = NSRange(rawValue.startIndex..<rawValue.endIndex, in: rawValue)
    return groupMailAddressExpression.matches(in: rawValue, range: range).compactMap { match in
        guard let range = Range(match.range, in: rawValue) else { return nil }
        return String(rawValue[range])
    }
}

func groupMailURL(for addresses: [String]) -> URL? {
    var seen = Set<String>()
    let recipients = addresses.compactMap { address -> String? in
        guard let trimmed = address.trimmedOrNil else { return nil }
        let key = trimmed.lowercased()
        guard seen.insert(key).inserted else { return nil }
        return trimmed
    }
    guard !recipients.isEmpty else { return nil }

    var components = URLComponents()
    components.scheme = "mailto"
    components.path = recipients.joined(separator: ",")
    return safeExternalURL(components.url)
}

extension GrantDataStore {
    func groupMailAddresses(
        authorIDs: [String] = [],
        presentedNames: [String] = []
    ) -> [String] {
        let currentUser = currentUserAuthor()
        let currentUserID = currentUser?.id
        let currentUserAddresses = Set(
            (currentUser?.affiliations ?? []).flatMap { affiliation in
                extractedGroupMailAddresses(from: affiliation.email).map { $0.lowercased() }
            }
        )
        var resolvedAuthors: [PublicationAuthor] = []
        var seenAuthorIDs = Set<String>()

        for author in authorIDs.compactMap({ publicationAuthor(id: $0) })
            where author.id != currentUserID && seenAuthorIDs.insert(author.id).inserted {
            resolvedAuthors.append(author)
        }
        for author in presentedNames.compactMap({ publicationAuthor(matchingPresentedName: $0) })
            where author.id != currentUserID && seenAuthorIDs.insert(author.id).inserted {
            resolvedAuthors.append(author)
        }

        var seenAddresses = Set<String>()
        return resolvedAuthors.flatMap { author in
            author.affiliations.flatMap { affiliation in
                extractedGroupMailAddresses(from: affiliation.email)
            }
        }
        .filter {
            let key = $0.lowercased()
            return !currentUserAddresses.contains(key) && seenAddresses.insert(key).inserted
        }
    }
}

struct GroupMailButton: View {
    let addresses: [String]
    let language: AppLanguage

    private var destination: URL? {
        groupMailURL(for: addresses)
    }

    var body: some View {
        Button {
            guard let destination else { return }
            NSWorkspace.shared.open(destination)
        } label: {
            Label(
                language.text("Group", "Grupp"),
                systemImage: "envelope.badge.plus"
            )
        }
        .buttonStyle(.bordered)
        .disabled(destination == nil)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var helpText: String {
        guard !addresses.isEmpty else {
            return language.text(
                "No e-mail addresses are available for these researchers.",
                "Det finns inga e-postadresser för dessa forskare."
            )
        }
        return language.text(
            "Create an e-mail to all \(addresses.count) addresses in the default mail app.",
            "Skapa e-post till alla \(addresses.count) adresser i den förvalda e-postappen."
        )
    }
}
