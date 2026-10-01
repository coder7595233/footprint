import SwiftUI

struct OrganizationContactPersonsSection: View {
    @Binding var contacts: [OrganizationEmployerContact]
    let language: AppLanguage
    private let emailActionWidth: CGFloat = 62
    private let contactActionWidth: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppPanelHeadingText(text: language.text("Contact persons", "Kontaktpersoner"))

            HStack(spacing: 10) {
                AppTableHeaderText(text: language.text("First name", "Förnamn")).frame(width: 120, alignment: .leading)
                AppTableHeaderText(text: language.text("Last name", "Efternamn")).frame(width: 150, alignment: .leading)
                AppTableHeaderText(text: language.text("Role", "Roll")).frame(width: 170, alignment: .leading)
                AppTableHeaderText(text: language.text("E-mail", "E-post")).frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: emailActionWidth)
                AppTableHeaderText(text: language.text("Phone", "Telefon")).frame(width: 150, alignment: .leading)
                Color.clear.frame(width: contactActionWidth)
            }

            ForEach(contacts, id: \.id) { contact in
                contactRow(contactID: contact.id)
            }
        }
    }

    @ViewBuilder
    private func contactRow(contactID: String) -> some View {
        if let index = contactIndex(for: contactID) {
            HStack(alignment: .top, spacing: 10) {
                TextField(language.text("First name", "Förnamn"), text: contactBinding(contactID: contactID, keyPath: \.firstName))
                    .appTextInputChrome()
                    .frame(width: 120)
                TextField(language.text("Last name", "Efternamn"), text: contactBinding(contactID: contactID, keyPath: \.lastName))
                    .appTextInputChrome()
                    .frame(width: 150)
                TextField(language.text("Role", "Roll"), text: contactBinding(contactID: contactID, keyPath: \.role))
                    .appTextInputChrome()
                    .frame(width: 170)
                HStack(alignment: .center, spacing: 8) {
                    TextField(language.text("E-mail", "E-post"), text: contactBinding(contactID: contactID, keyPath: \.email))
                        .appTextInputChrome()
                        .frame(minWidth: 220)
                    if let mailURL = contactMailURL(for: contactID) {
                        AppDestinationURLLink(
                            kind: .email,
                            language: language,
                            destination: mailURL,
                            fontSize: 12,
                            width: emailActionWidth,
                            height: AppPalette.fieldMinHeight
                        )
                    } else {
                        AppDestinationPlaceholder(width: emailActionWidth, height: AppPalette.fieldMinHeight)
                    }
                }
                TextField(language.text("Phone", "Telefon"), text: contactBinding(contactID: contactID, keyPath: \.phone))
                    .appTextInputChrome()
                    .frame(width: 150)

                if !contacts[index].isEmpty {
                    AppIconDeleteButton(
                        title: language.text("Delete", "Ta bort"),
                        width: contactActionWidth,
                        cancelTitle: language.text("Cancel", "Avbryt"),
                        confirmationTitle: language.text("Delete contact?", "Ta bort kontakten?")
                    ) {
                        removeContact(contactID: contactID)
                    }
                    .frame(height: AppPalette.fieldMinHeight)
                } else {
                    Color.clear
                        .frame(width: contactActionWidth, height: AppPalette.fieldMinHeight)
                }
            }
        }
    }

    private func contactIndex(for contactID: String) -> Int? {
        contacts.firstIndex(where: { $0.id == contactID })
    }

    private func contactMailURL(for contactID: String) -> URL? {
        guard let index = contactIndex(for: contactID) else { return nil }
        return singleRecipientMailtoURL(contacts[index].email)
    }

    private func removeContact(contactID: String) {
        guard let index = contactIndex(for: contactID) else { return }
        contacts.remove(at: index)
        contacts = Self.normalizedContacts(contacts)
    }

    private func contactBinding(
        contactID: String,
        keyPath: WritableKeyPath<OrganizationEmployerContact, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let index = contactIndex(for: contactID) else { return "" }
                return contacts[index][keyPath: keyPath]
            },
            set: { newValue in
                updateContactRow(contactID: contactID) { contact in
                    contact[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func updateContactRow(contactID: String, mutate: (inout OrganizationEmployerContact) -> Void) {
        guard let index = contactIndex(for: contactID) else { return }
        mutate(&contacts[index])
        ensureTrailingContactRow(afterEditing: index)
        contacts = Self.normalizedContacts(contacts)
    }

    private func ensureTrailingContactRow(afterEditing index: Int) {
        guard contacts.indices.contains(index) else { return }
        let isLastRow = index == contacts.index(before: contacts.endIndex)
        guard isLastRow, !contacts[index].isEmpty else { return }
        contacts.append(OrganizationEmployerContact())
    }

    private static func normalizedContacts(_ contacts: [OrganizationEmployerContact]) -> [OrganizationEmployerContact] {
        var normalized = contacts
            .map {
                OrganizationEmployerContact(
                    id: $0.id,
                    role: $0.role.trimmingCharacters(in: .whitespacesAndNewlines),
                    firstName: $0.firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastName: $0.lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: $0.phone.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: $0.email.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.isEmpty }
        let trailingPlaceholder = contacts.last(where: \.isEmpty) ?? OrganizationEmployerContact()
        normalized.append(trailingPlaceholder)
        return normalized
    }
}
