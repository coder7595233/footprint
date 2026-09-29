import Foundation

@MainActor
extension GrantDataStore {
    func autosaveOrganizationProjectTasks(_ organization: OrganizationRecord) {
        autosaveOrganization(
            id: organization.id,
            nameSv: organization.nameSv,
            nameEn: organization.nameEn,
            addressLine: organization.addressLine,
            postalCode: organization.postalCode,
            city: organization.city,
            country: organization.country,
            category: organization.category,
            roles: organization.roles,
            note: organization.note,
            websiteURL: organization.websiteURL,
            phoneNumber: organization.phoneNumber,
            organizationNumber: organization.organizationNumber,
            vatNumber: organization.vatNumber,
            employerContacts: organization.employerContacts,
            flag: organization.flag,
            membershipFrom: organization.membershipFrom,
            membershipTo: organization.membershipTo,
            congresses: organization.congresses,
            projectTasks: organization.projectTasks,
            salaryCalculator: organization.salaryCalculator
        )
    }

}
