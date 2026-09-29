import Foundation

// MARK: - "Kopiera till nästa år" (round 10)
//
// A call ("utlysning") is a new record every year. Copying a record makes the
// next year's record: the same funder, call, rules, fund manager, project and
// co-applicants, with every call date one year later. What belongs to the
// earlier application and grant (amounts, outcome, case numbers, the grant
// part) is left empty.

extension GrantApplication {
    /// The record for next year's call. `newID` and `rowNumber` identify the
    /// copy; `status` is its starting status ("Att söka").
    func copiedToNextYear(newID: String, rowNumber: Int, status: String) -> GrantApplication {
        var copy = GrantApplication(
            id: newID,
            rowNumber: rowNumber,
            organizationID: organizationID,
            organization: organization,
            grantName: grantNameSv,
            grantNameSv: grantApplicationYearShifted(grantNameSv),
            grantNameEn: grantApplicationYearShifted(grantNameEn),
            grantCategory: grantCategory,
            currency: currency,
            maxAmount: maxAmount,
            yearCount: yearCount,
            employmentPercentage: employmentPercentage,
            employmentMonths: employmentMonths,
            salaryIncludesOverhead: salaryIncludesOverhead,
            opensOn: grantApplicationDateShiftedOneYear(opensOn),
            opensOnUncertain: opensOnUncertain,
            closesOn: grantApplicationDateShiftedOneYear(closesOn),
            closesOnUncertain: closesOnUncertain,
            decisionExpectedOn: grantApplicationDateShiftedOneYear(decisionExpectedOn),
            decisionExpectedOnUncertain: decisionExpectedOnUncertain,
            firstDispositionOn: grantApplicationDateShiftedOneYear(firstDispositionOn),
            firstDispositionOnUncertain: firstDispositionOnUncertain,
            lastDispositionOn: grantApplicationDateShiftedOneYear(lastDispositionOn),
            lastDispositionOnUncertain: lastDispositionOnUncertain,
            projectID: projectID,
            projectType: projectType,
            dispositionYears: dispositionYears.map(grantApplicationYearShifted),
            applicantCriteria: applicantCriteria,
            projectCriteria: projectCriteria,
            primaryLink: primaryLink,
            result: status,
            applicationManagerID: applicationManagerID,
            applicationManager: applicationManager,
            managerReason: managerReason,
            applicationTitle: applicationTitle,
            coApplicants: coApplicants,
            coApplicantAuthorIDs: coApplicantAuthorIDs,
            appliedYear: appliedYear.map(grantApplicationYearShifted),
            fundingSalary: fundingSalary,
            fundingMaterials: fundingMaterials,
            fundingPhDStudents: fundingPhDStudents
        )
        copy.isEditingLocked = false
        return copy
    }
}

/// An ISO day one year later ("2028-02-29" becomes "2029-02-28"); a bare
/// year becomes the next year; anything else is kept as it is.
func grantApplicationDateShiftedOneYear(_ raw: String?) -> String? {
    guard let raw = raw?.trimmedOrNil else { return raw }
    let canonical = DateParsers.canonicalizedDayInput(raw)
    if let date = DateParsers.isoDay.date(from: canonical),
       let shifted = Calendar.current.date(byAdding: .year, value: 1, to: date) {
        return DateParsers.isoDay.string(from: shifted)
    }
    return grantApplicationYearShifted(raw)
}

/// Every year (1990–2100) written in the text one higher, so "Forsknings-ALF
/// 2027" becomes "Forsknings-ALF 2028". Other numbers are left alone.
func grantApplicationYearShifted(_ text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(19[9]\d|20\d\d|2100)(?!\d)"#) else { return text }
    let nsText = text as NSString
    var result = ""
    var cursor = 0
    for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
        result += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        let year = Int(nsText.substring(with: match.range)) ?? 0
        result += String(year + 1)
        cursor = match.range.location + match.range.length
    }
    result += nsText.substring(from: cursor)
    return result
}

extension GrantDataStore {
    /// "Kopiera till nästa år": adds next year's record for the call and
    /// returns its id. Nil when the record is not found.
    @discardableResult
    func copyApplicationToNextYear(id: String) -> String? {
        guard let source = applications.first(where: { $0.id == id }) else { return nil }
        let newID = UUID().uuidString
        let nextRow = (applications.map(\.rowNumber).max() ?? 0) + 1
        let copy = source.copiedToNextYear(
            newID: newID,
            rowNumber: nextRow,
            status: workflowDefaultSettings.resolvedStatus
        )
        performUndoableChange(
            actionName: language.text("Copy to next year", "Kopiera till nästa år"),
            successMessage: language.text("Created next year's record.", "Skapade nästa års post."),
            failureMessage: language.text("Could not copy the record.", "Kunde inte kopiera posten."),
            scope: .applications
        ) {
            applications.insert(copy, at: 0)
        }
        return newID
    }
}
