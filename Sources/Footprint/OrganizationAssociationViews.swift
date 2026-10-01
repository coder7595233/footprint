import SwiftUI

struct OrganizationAssociationSection: View {
    @ObservedObject var store: GrantDataStore
    let organizationID: String
    @Binding var membershipFrom: String
    @Binding var membershipTo: String
    @Binding var congressRows: [OrganizationCongress]
    let linkedContributions: [CVConferenceContribution]
    let language: AppLanguage
    let openContribution: (CVConferenceContribution) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Member from", "Medlem från"))
                        .font(appFont(.tableHeader))
                    AppYearField(text: $membershipFrom, language: language, width: 120)
                }
                .frame(width: 120, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text("Member to", "Medlem till"))
                        .font(appFont(.tableHeader))
                    AppYearField(text: $membershipTo, language: language, width: 120)
                }
                .frame(width: 120, alignment: .leading)

                Spacer(minLength: 0)
            }
        }
    }
}
