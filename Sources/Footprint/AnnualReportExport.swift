import Foundation

private struct AnnualReportTeachingHours {
    var doctoral: Double = 0
    var clinical: Double = 0
    var other: Double = 0

    var total: Double {
        doctoral + clinical + other
    }
}

private enum AnnualReportGrantStatus {
    case waiting
    case granted
    case rejected
}

extension GrantDataStore {
    func annualReportPreviewDocument(
        year: Int,
        exportLanguage: AppLanguage,
        includeCoApplicantGrants: Bool = false,
        layout: ExportDocumentLayoutOptions
    ) -> CVExportDocument {
        var payload = annualReportDocument(year: year, exportLanguage: exportLanguage, includeCoApplicantGrants: includeCoApplicantGrants)
        applyLayout(layout, to: &payload, exportLanguage: exportLanguage)
        return payload
    }

    private func annualReportDocument(year: Int, exportLanguage: AppLanguage, includeCoApplicantGrants: Bool) -> CVExportDocument {
        let author = currentUserAuthor()
        let name = author?.name.nonEmpty ?? annualReportText(exportLanguage, english: "CV profile", swedish: "CV-profil")
        let userPublications = annualReportCurrentUserPublications()
        let publishedPeerReviewed = userPublications.filter {
            $0.isPublished && $0.isPeerReviewed && $0.yearValue == year
        }
        // Round 12 (user decision 2026-09-30): by default only grants where
        // the user is main applicant; co-applicant grants on request.
        let grants = annualReportCurrentUserGrantApplications().filter {
            annualReportYearValue($0.statsYear) == year && annualReportGrantStatus($0) != nil
                && (includeCoApplicantGrants || annualReportCurrentUserIsFirstApplicant($0))
        }
        let teaching = annualReportTeachingHours(year: year)
        let citationEntries = userPublications.flatMap(\.citationYears).filter {
            annualReportYearValue($0.year) == year
        }
        let externalCitations = citationEntries.map(\.countValue).reduce(0, +)
        let selfCitations = citationEntries.map(\.selfCitationCountValue).reduce(0, +)
        let jifValues = publishedPeerReviewed.compactMap(annualReportJIFValue)
        let averageJIF = jifValues.isEmpty ? nil : jifValues.reduce(0, +) / Double(jifValues.count)
        let totalJIF = jifValues.isEmpty ? nil : jifValues.reduce(0, +)

        let overviewRows = [
            [
                annualReportText(exportLanguage, english: "Published peer-reviewed publications", swedish: "Publicerade sakkunniggranskade publikationer"),
                "\(publishedPeerReviewed.count)",
            ],
            [
                annualReportText(exportLanguage, english: "Grant applications", swedish: "Anslagsansökningar"),
                "\(grants.count)",
            ],
            [
                annualReportText(exportLanguage, english: "Teaching hours", swedish: "Undervisningstimmar"),
                annualReportHoursText(teaching.total, language: exportLanguage),
            ],
            [
                annualReportText(exportLanguage, english: "Citations during the year", swedish: "Citeringar under året"),
                "\(externalCitations + selfCitations)",
            ],
        ]

        let summarySection = CVExportSection(
            title: annualReportText(exportLanguage, english: "Summary", swedish: "Sammanfattning"),
            headers: [
                annualReportText(exportLanguage, english: "Area", swedish: "Område"),
                annualReportText(exportLanguage, english: "Value", swedish: "Värde"),
            ],
            rows: overviewRows
        )

        let summarySections = ([
            summarySection,
            annualReportGrantSection(grants: grants, year: year, language: exportLanguage, includeCoApplicantGrants: includeCoApplicantGrants),
            annualReportPublicationSection(
                publications: userPublications,
                publishedPeerReviewed: publishedPeerReviewed,
                year: year,
                externalCitations: externalCitations,
                selfCitations: selfCitations,
                averageJIF: averageJIF,
                totalJIF: totalJIF,
                language: exportLanguage
            ),
            annualReportTeachingSection(teaching: teaching, language: exportLanguage),
            annualReportMeritsSection(year: year, language: exportLanguage),
        ])
        .filter { !$0.rows.isEmpty || !$0.items.isEmpty || !$0.paragraphs.isEmpty || !$0.subsections.isEmpty }
        var detailSections = annualReportDetailSections(
            grants: grants,
            publications: userPublications,
            publishedPeerReviewed: publishedPeerReviewed,
            year: year,
            language: exportLanguage
        )
        .filter { !$0.rows.isEmpty || !$0.items.isEmpty || !$0.paragraphs.isEmpty || !$0.subsections.isEmpty }
        if !detailSections.isEmpty {
            detailSections[0].layoutKind = "pageBreakBefore"
        }
        let sections = summarySections + detailSections

        return CVExportDocument(
            style: CVDocumentExportStyle.own.rawValue,
            exportLanguage: exportLanguage.rawValue,
            highlightName: "",
            title: annualReportText(exportLanguage, english: "ANNUAL REPORT \(year)", swedish: "ÅRSRAPPORT \(year)"),
            subtitle: name,
            summaryLines: [],
            summaryRichParagraphs: [],
            sections: sections
        )
    }

    private func annualReportGrantSection(
        grants: [GrantApplication],
        year: Int,
        language: AppLanguage,
        includeCoApplicantGrants: Bool
    ) -> CVExportSection {
        let mainApplicantGrants = grants.filter(annualReportCurrentUserIsFirstApplicant)
        let coApplicantGrants = grants.filter { !annualReportCurrentUserIsFirstApplicant($0) }

        func awardedCount(_ source: [GrantApplication]) -> String {
            "\(source.filter(\.isGranted).count)"
        }

        func statusCount(_ source: [GrantApplication], status: AnnualReportGrantStatus) -> String {
            "\(source.filter { annualReportGrantStatus($0) == status }.count)"
        }

        func awardedAmount(_ source: [GrantApplication]) -> String {
            annualReportCurrencyText(source.filter(\.isGranted).map(annualReportGrantAmount).reduce(0, +), language: language)
        }

        func representedAmount(_ source: [GrantApplication]) -> String {
            annualReportCurrencyText(source.map(annualReportGrantAmount).reduce(0, +), language: language)
        }

        let section = CVExportSection(
            title: annualReportText(language, english: "Grants", swedish: "Anslag"),
            headers: [
                annualReportText(language, english: "Metric", swedish: "Mått"),
                annualReportText(language, english: "Main applicant", swedish: "Huvudsökande"),
                annualReportText(language, english: "Co-applicant", swedish: "Medsökande"),
            ],
            rows: [
                [
                    annualReportText(language, english: "Applications", swedish: "Ansökningar"),
                    "\(mainApplicantGrants.count)",
                    "\(coApplicantGrants.count)",
                ],
                [
                    annualReportText(language, english: "Awarded", swedish: "Beviljade"),
                    awardedCount(mainApplicantGrants),
                    awardedCount(coApplicantGrants),
                ],
                [
                    annualReportText(language, english: "Pending decision", swedish: "Väntar beslut"),
                    statusCount(mainApplicantGrants, status: .waiting),
                    statusCount(coApplicantGrants, status: .waiting),
                ],
                [
                    annualReportText(language, english: "Declined", swedish: "Avslagna"),
                    statusCount(mainApplicantGrants, status: .rejected),
                    statusCount(coApplicantGrants, status: .rejected),
                ],
                [
                    annualReportText(language, english: "Awarded amount", swedish: "Beviljat belopp"),
                    awardedAmount(mainApplicantGrants),
                    awardedAmount(coApplicantGrants),
                ],
                [
                    annualReportText(language, english: "Total amount represented", swedish: "Totalt belopp i underlaget"),
                    representedAmount(mainApplicantGrants),
                    representedAmount(coApplicantGrants),
                ],
            ]
        )
        guard !includeCoApplicantGrants else { return section }
        // Only main applicant: the co-applicant column is left out.
        var mainOnly = section
        mainOnly.headers = Array(section.headers.prefix(2))
        mainOnly.rows = section.rows.map { Array($0.prefix(2)) }
        return mainOnly
    }

    private func annualReportPublicationSection(
        publications: [PublicationRecord],
        publishedPeerReviewed: [PublicationRecord],
        year: Int,
        externalCitations: Int,
        selfCitations: Int,
        averageJIF: Double?,
        totalJIF: Double?,
        language: AppLanguage
    ) -> CVExportSection {
        let originals = publishedPeerReviewed.filter { annualReportPublicationTypeBucket($0) == "original" }
        let reviews = publishedPeerReviewed.filter { annualReportPublicationTypeBucket($0) == "review" }
        let others = publishedPeerReviewed.filter { annualReportPublicationTypeBucket($0) == "other" }
        let submittedOrAccepted = publications.filter {
            annualReportPublicationStatusYear($0) == year &&
                (PublicationStatus.fromStored($0.statusLabel) == .submitted || PublicationStatus.fromStored($0.statusLabel) == .accepted)
        }
        let inPreparation = publications.filter {
            annualReportPublicationStatusYear($0) == year && PublicationStatus.fromStored($0.statusLabel) == .inPreparation
        }

        return CVExportSection(
            title: annualReportText(language, english: "Publications", swedish: "Publikationer"),
            headers: [
                annualReportText(language, english: "Metric", swedish: "Mått"),
                annualReportText(language, english: "Value", swedish: "Värde"),
            ],
            rows: [
                [annualReportText(language, english: "Published peer-reviewed", swedish: "Publicerade sakkunniggranskade"), "\(publishedPeerReviewed.count)"],
                [annualReportText(language, english: "Original articles", swedish: "Originalartiklar"), "\(originals.count)"],
                [annualReportText(language, english: "Review articles", swedish: "Översiktsartiklar"), "\(reviews.count)"],
                [annualReportText(language, english: "Other peer-reviewed", swedish: "Övriga sakkunniggranskade"), "\(others.count)"],
                [annualReportText(language, english: "Submitted or accepted manuscripts", swedish: "Inskickade eller accepterade manuskript"), "\(submittedOrAccepted.count)"],
                [annualReportText(language, english: "Manuscripts in preparation", swedish: "Manuskript under arbete"), "\(inPreparation.count)"],
                [annualReportText(language, english: "External citations", swedish: "Externa citeringar"), "\(externalCitations)"],
                [annualReportText(language, english: "Self-citations", swedish: "Självciteringar"), "\(selfCitations)"],
                [annualReportText(language, english: "Average JIF", swedish: "Genomsnittligt JIF"), annualReportOptionalDecimalText(averageJIF, language: language)],
                [annualReportText(language, english: "Total JIF", swedish: "Totalt JIF"), annualReportOptionalDecimalText(totalJIF, language: language)],
            ]
        )
    }

    private func annualReportTeachingSection(
        teaching: AnnualReportTeachingHours,
        language: AppLanguage
    ) -> CVExportSection {
        CVExportSection(
            title: annualReportText(language, english: "Teaching", swedish: "Undervisning"),
            headers: [
                annualReportText(language, english: "Category", swedish: "Kategori"),
                annualReportText(language, english: "Hours", swedish: "Timmar"),
            ],
            rows: [
                [annualReportText(language, english: "Doctoral level", swedish: "Doktoral nivå"), annualReportHoursText(teaching.doctoral, language: language)],
                [annualReportText(language, english: "Clinical teaching", swedish: "Klinisk undervisning"), annualReportHoursText(teaching.clinical, language: language)],
                [annualReportText(language, english: "Other teaching", swedish: "Övrig undervisning"), annualReportHoursText(teaching.other, language: language)],
                [annualReportText(language, english: "Total", swedish: "Totalt"), annualReportHoursText(teaching.total, language: language)],
            ]
        )
    }

    private func annualReportMeritsSection(year: Int, language: AppLanguage) -> CVExportSection {
        let currentAuthorID = currentUserAuthor()?.id
        // Round 12: only submitted and accepted contributions count.
        let conferences = cvConferenceContributions.filter {
            $0.isCVReportable && annualReportYearValue($0.to.nonEmpty ?? $0.from) == year
        }
        let media = cvMediaAppearances.filter {
            annualReportYearValue($0.publicationDate) == year && mediaAppearanceIncludesCurrentUser($0)
        }
        let reviews = cvReviewEntries.filter {
            annualReportYearValue($0.date) == year && ($0.authorID?.trimmedOrNil == nil || $0.authorID == currentAuthorID)
        }

        return CVExportSection(
            title: annualReportText(language, english: "Dissemination and assignments", swedish: "Spridning och uppdrag"),
            headers: [
                annualReportText(language, english: "Merit", swedish: "Merit"),
                annualReportText(language, english: "Count", swedish: "Antal"),
            ],
            rows: [
                [annualReportText(language, english: "Conference contributions", swedish: "Konferensbidrag"), "\(conferences.count)"],
                [annualReportText(language, english: "Media appearances", swedish: "Medverkan i media"), "\(media.count)"],
                [annualReportText(language, english: "Reviews and expert assignments", swedish: "Gransknings- och sakkunniguppdrag"), "\(reviews.count)"],
            ]
        )
    }

    private func annualReportDetailSections(
        grants: [GrantApplication],
        publications: [PublicationRecord],
        publishedPeerReviewed: [PublicationRecord],
        year: Int,
        language: AppLanguage
    ) -> [CVExportSection] {
        annualReportGrantDetailSections(grants: grants, language: language)
            .filter { !$0.rows.isEmpty || !$0.title.contains(annualReportText(language, english: "co-applicant", swedish: "medsökande")) } + [
            annualReportPublicationDetailSection(
                publications: publications,
                publishedPeerReviewed: publishedPeerReviewed,
                year: year,
                language: language
            ),
            annualReportTeachingDetailSection(year: year, language: language),
        ] + annualReportMeritDetailSections(year: year, language: language)
    }

    private func annualReportGrantDetailSections(
        grants: [GrantApplication],
        language: AppLanguage
    ) -> [CVExportSection] {
        func rows(for source: [GrantApplication]) -> [(row: [String], sourceID: String)] {
            source
            .sorted {
                let leftDate = annualReportGrantDetailDate($0)
                let rightDate = annualReportGrantDetailDate($1)
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
            .map { application in
                let amount = annualReportGrantAmount(application)
                return (
                    row: [
                        annualReportGrantStatusText(annualReportGrantStatus(application), language: language),
                        annualReportDisplayDate(annualReportGrantDetailDate(application), language: language),
                        funderName(for: application).nonEmpty ?? "–",
                        application.localizedGrantName(language: language).nonEmpty ?? application.grantName.nonEmpty ?? application.displayTitle,
                        annualReportSEKAmountText(amount, language: language),
                    ],
                    sourceID: "application-\(application.id)"
                )
            }
        }

        let mainApplicantRows = rows(for: grants.filter(annualReportCurrentUserIsFirstApplicant))
        let coApplicantRows = rows(for: grants.filter { !annualReportCurrentUserIsFirstApplicant($0) })
        let headers = [
            annualReportText(language, english: "Status", swedish: "Status"),
            annualReportText(language, english: "Date", swedish: "Datum"),
            annualReportText(language, english: "Funder", swedish: "Finansiär"),
            annualReportText(language, english: "Grant", swedish: "Anslag"),
            annualReportText(language, english: "Amount in SEK", swedish: "Belopp i SEK"),
        ]

        return [
            CVExportSection(
                title: annualReportText(language, english: "Detailed records - Grants, main applicant", swedish: "Detaljerade poster - anslag, huvudsökande"),
                headers: headers,
                rows: mainApplicantRows.map { $0.row },
                itemSourceIDs: mainApplicantRows.map { $0.sourceID }
            ),
            CVExportSection(
                title: annualReportText(language, english: "Detailed records - Grants, co-applicant", swedish: "Detaljerade poster - anslag, medsökande"),
                headers: headers,
                rows: coApplicantRows.map { $0.row },
                itemSourceIDs: coApplicantRows.map { $0.sourceID }
            ),
        ]
    }

    private func annualReportPublicationDetailSection(
        publications: [PublicationRecord],
        publishedPeerReviewed: [PublicationRecord],
        year: Int,
        language: AppLanguage
    ) -> CVExportSection {
        let publishedIDs = Set(publishedPeerReviewed.map(\.id))
        let items = publications
            .filter { publication in
                let status = PublicationStatus.fromStored(publication.statusLabel)
                let isManuscriptIncluded = annualReportPublicationStatusYear(publication) == year &&
                    (status == .submitted || status == .accepted || status == .inPreparation)
                return publishedIDs.contains(publication.id) || isManuscriptIncluded
            }
            .sorted {
                let leftRank = annualReportPublicationDetailRank($0, publishedIDs: publishedIDs)
                let rightRank = annualReportPublicationDetailRank($1, publishedIDs: publishedIDs)
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                let leftYear = annualReportPublicationStatusYear($0) ?? $0.yearValue ?? 0
                let rightYear = annualReportPublicationStatusYear($1) ?? $1.yearValue ?? 0
                if leftYear != rightYear {
                    return leftYear > rightYear
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .map { publication in
                let citationEntries = publication.citationYears.filter { annualReportYearValue($0.year) == year }
                let externalCitations = citationEntries.map(\.countValue).reduce(0, +)
                let selfCitations = citationEntries.map(\.selfCitationCountValue).reduce(0, +)
                let jif = publishedIDs.contains(publication.id) ? annualReportJIFValue(publication) : nil
                return (
                    row: [
                        annualReportPublicationStatusText(PublicationStatus.fromStored(publication.statusLabel), language: language),
                        publication.publicationType.nonEmpty ?? "–",
                        publication.title.nonEmpty ?? "–",
                        publication.journal.nonEmpty ?? "–",
                        "\(externalCitations + selfCitations)",
                        annualReportOptionalDecimalText(jif, language: language),
                    ],
                    sourceID: "publication-\(publication.id)"
                )
            }

        return CVExportSection(
            title: annualReportText(language, english: "Detailed records - Publications", swedish: "Detaljerade poster - publikationer"),
            headers: [
                annualReportText(language, english: "Status", swedish: "Status"),
                annualReportText(language, english: "Type", swedish: "Typ"),
                annualReportText(language, english: "Title", swedish: "Titel"),
                annualReportText(language, english: "Journal", swedish: "Tidskrift"),
                annualReportText(language, english: "Citations", swedish: "Citeringar"),
                "JIF",
            ],
            rows: items.map { $0.row },
            itemSourceIDs: items.map { $0.sourceID }
        )
    }

    private func annualReportTeachingDetailSection(year: Int, language: AppLanguage) -> CVExportSection {
        let contextsByID = Dictionary(uniqueKeysWithValues: teachingCourses.map { ($0.id, $0) })
        let doctoralSourceAssignmentIDs = Set(doctoralCandidates.flatMap(\.sourceAssignmentIDs))
        var sortedRows: [(sortDate: String, row: [String], sourceID: String)] = []

        for assignment in teachingAssignments where !doctoralSourceAssignmentIDs.contains(assignment.id) {
            let context = assignment.contextID.flatMap { contextsByID[$0] }
            let title = annualReportTeachingDetailTitle(assignment: assignment, context: context, language: language)
            let category = annualReportTeachingCategoryLabel(assignment: assignment, context: context, language: language)
            for period in assignment.periods where !period.isEmpty {
                guard let hoursPerTerm = GrantParsing.numericValue(from: period.hoursPerTerm), hoursPerTerm > 0 else { continue }
                let matchingTermCount = annualReportTeachingTerms(from: period.from, to: period.to)
                    .filter { $0.year == year }
                    .count
                guard matchingTermCount > 0 else { continue }
                let hours = Double(matchingTermCount) * hoursPerTerm
                sortedRows.append((
                    sortDate: period.to.nonEmpty ?? period.from.nonEmpty ?? "",
                    row: [
                        category,
                        annualReportTeachingDetailDateRange(from: period.from, to: period.to, year: year, language: language),
                        title,
                        annualReportHoursText(hours, language: language),
                    ],
                    sourceID: "teaching-\(assignment.id)"
                ))
            }
        }

        for candidate in doctoralCandidates {
            let title = [candidate.candidateName.nonEmpty, candidate.doctoralProjectName.nonEmpty]
                .compactMap { $0 }
                .joined(separator: " - ")
                .nonEmpty ?? annualReportText(language, english: "Doctoral candidate", swedish: "Doktorand")
            for period in candidate.supervisionPeriods where !period.isEmpty {
                // Round 12: hours in proportion to days (one rule everywhere).
                let hours = period.supervisionHours(inYear: year, untilReferenceDate: false)
                guard hours > 0 else { continue }
                sortedRows.append((
                    sortDate: period.to.nonEmpty ?? period.from.nonEmpty ?? "",
                    row: [
                        annualReportText(language, english: "Doctoral level", swedish: "Doktoral nivå"),
                        annualReportTeachingDetailDateRange(from: period.from, to: period.to, year: year, language: language),
                        title,
                        annualReportHoursText(hours, language: language),
                    ],
                    sourceID: "doctoral-\(candidate.id)"
                ))
            }
        }

        let items = sortedRows
            .sorted {
                if $0.sortDate != $1.sortDate {
                    return $0.sortDate > $1.sortDate
                }
                return $0.row[2].localizedStandardCompare($1.row[2]) == .orderedAscending
            }

        return CVExportSection(
            title: annualReportText(language, english: "Detailed records - Teaching", swedish: "Detaljerade poster - undervisning"),
            headers: [
                annualReportText(language, english: "Category", swedish: "Kategori"),
                annualReportText(language, english: "Period", swedish: "Period"),
                annualReportText(language, english: "Activity", swedish: "Aktivitet"),
                annualReportText(language, english: "Hours", swedish: "Timmar"),
            ],
            rows: items.map { $0.row },
            itemSourceIDs: items.map { $0.sourceID }
        )
    }

    private func annualReportMeritDetailSections(year: Int, language: AppLanguage) -> [CVExportSection] {
        let currentAuthorID = currentUserAuthor()?.id
        var journalReviewRows: [(sortDate: String, row: [String], sourceID: String)] = []
        var otherRows: [(sortDate: String, row: [String], sourceID: String)] = []

        for contribution in cvConferenceContributions
        where contribution.isCVReportable && annualReportYearValue(contribution.to.nonEmpty ?? contribution.from) == year {
            otherRows.append((
                sortDate: contribution.to.nonEmpty ?? contribution.from,
                row: [
                    annualReportText(language, english: "Conference contribution", swedish: "Konferensbidrag"),
                    annualReportDateRange(from: contribution.from, to: contribution.to, language: language),
                    contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    contribution.localizedName(language: language).nonEmpty ?? "–",
                ],
                sourceID: "conference-\(contribution.id)"
            ))
        }

        for appearance in cvMediaAppearances where annualReportYearValue(appearance.publicationDate) == year && mediaAppearanceIncludesCurrentUser(appearance) {
            otherRows.append((
                sortDate: appearance.publicationDate,
                row: [
                    annualReportText(language, english: "Media appearance", swedish: "Medverkan i media"),
                    annualReportDisplayDate(appearance.publicationDate, language: language),
                    appearance.localizedTitle(language: language).nonEmpty ?? appearance.displayTitle,
                    appearance.localizedDescription(language: language).nonEmpty ?? appearance.link.nonEmpty ?? "–",
                ],
                sourceID: "media-\(appearance.id)"
            ))
        }

        for review in cvReviewEntries where annualReportYearValue(review.date) == year && (review.authorID?.trimmedOrNil == nil || review.authorID == currentAuthorID) {
            let context = [review.organizationName.nonEmpty, review.journalName.nonEmpty, review.programName.nonEmpty]
                .compactMap { $0 }
                .joined(separator: " - ")
                .nonEmpty ?? "–"
            if review.category == .journalReview {
                journalReviewRows.append((
                    sortDate: review.date,
                    row: [
                        annualReportDisplayDate(review.date, language: language),
                        review.displayTitle,
                        context,
                    ],
                    sourceID: "review-\(review.id)"
                ))
            } else {
                otherRows.append((
                    sortDate: review.date,
                    row: [
                        review.category.localizedTitle(language),
                        annualReportDisplayDate(review.date, language: language),
                        review.displayTitle,
                        context,
                    ],
                    sourceID: "review-\(review.id)"
                ))
            }
        }

        func sorted(
            _ rows: [(sortDate: String, row: [String], sourceID: String)],
            titleIndex: Int
        ) -> [(row: [String], sourceID: String)] {
            rows
            .sorted {
                if $0.sortDate != $1.sortDate {
                    return $0.sortDate > $1.sortDate
                }
                return $0.row[titleIndex].localizedStandardCompare($1.row[titleIndex]) == .orderedAscending
            }
            .map { (row: $0.row, sourceID: $0.sourceID) }
        }

        let sortedJournalReviewRows = sorted(journalReviewRows, titleIndex: 1)
        let sortedOtherRows = sorted(otherRows, titleIndex: 2)

        let journalReviewHeaders = [
            annualReportText(language, english: "Date", swedish: "Datum"),
            annualReportText(language, english: "Title", swedish: "Titel"),
            annualReportText(language, english: "Context", swedish: "Sammanhang"),
        ]
        let otherHeaders = [
            annualReportText(language, english: "Type", swedish: "Typ"),
            annualReportText(language, english: "Date", swedish: "Datum"),
            annualReportText(language, english: "Title", swedish: "Titel"),
            annualReportText(language, english: "Context", swedish: "Sammanhang"),
        ]

        return [
            CVExportSection(
                title: annualReportText(language, english: "Detailed records - Journal reviews", swedish: "Detaljerade poster - tidskriftsreviews"),
                headers: journalReviewHeaders,
                rows: sortedJournalReviewRows.map { $0.row },
                itemSourceIDs: sortedJournalReviewRows.map { $0.sourceID }
            ),
            CVExportSection(
                title: annualReportText(language, english: "Detailed records - Other assignments", swedish: "Detaljerade poster - övriga uppdrag"),
                headers: otherHeaders,
                rows: sortedOtherRows.map { $0.row },
                itemSourceIDs: sortedOtherRows.map { $0.sourceID }
            ),
        ]
    }

    private func annualReportGrantDetailDate(_ application: GrantApplication) -> String {
        application.resolvedDecisionDateString.nonEmpty
            ?? application.grantedOn.nonEmpty
            ?? application.deniedOn.nonEmpty
            ?? application.appliedOn.nonEmpty
            ?? application.closesOn.nonEmpty
            ?? ""
    }

    private func annualReportGrantStatusText(_ status: AnnualReportGrantStatus?, language: AppLanguage) -> String {
        switch status {
        case .waiting:
            return annualReportText(language, english: "Pending decision", swedish: "Väntar beslut")
        case .granted:
            return annualReportText(language, english: "Awarded", swedish: "Beviljad")
        case .rejected:
            return annualReportText(language, english: "Declined", swedish: "Avslagen")
        case nil:
            return "–"
        }
    }

    private func annualReportPublicationStatusText(_ status: PublicationStatus, language: AppLanguage) -> String {
        switch status {
        case .planned, .inPreparation:
            return annualReportText(language, english: "In preparation", swedish: "Under arbete")
        case .submitted:
            return annualReportText(language, english: "Submitted", swedish: "Inskickad")
        case .accepted:
            return annualReportText(language, english: "Accepted", swedish: "Accepterad")
        case .rejected:
            return annualReportText(language, english: "Rejected", swedish: "Refuserad")
        case .published:
            return annualReportText(language, english: "Published", swedish: "Publicerad")
        }
    }

    private func annualReportPublicationDetailRank(_ publication: PublicationRecord, publishedIDs: Set<String>) -> Int {
        if publishedIDs.contains(publication.id) {
            return 0
        }
        switch PublicationStatus.fromStored(publication.statusLabel) {
        case .submitted, .accepted:
            return 1
        case .planned, .inPreparation:
            return 2
        case .rejected:
            return 3
        case .published:
            return 0
        }
    }

    private func annualReportTeachingCategoryLabel(
        assignment: TeachingAssignment,
        context: TeachingCourse?,
        language: AppLanguage
    ) -> String {
        let isDoctoralReport =
            assignment.reportCategory == .doctoralCourseTeaching ||
            assignment.reportCategory == .doctoralPrincipalSupervision ||
            assignment.reportCategory == .doctoralAssistantSupervision
        let isDoctoral = isDoctoralReport || context?.level == .doctoral || context?.contextType == .doctoralEducation
        if isDoctoral {
            return annualReportText(language, english: "Doctoral level", swedish: "Doktoral nivå")
        }
        if context?.contextType == .clinicalTeaching {
            return annualReportText(language, english: "Clinical teaching", swedish: "Klinisk undervisning")
        }
        return annualReportText(language, english: "Other teaching", swedish: "Övrig undervisning")
    }

    private func annualReportTeachingDetailTitle(
        assignment: TeachingAssignment,
        context: TeachingCourse?,
        language: AppLanguage
    ) -> String {
        [
            assignment.activityName.nonEmpty,
            context?.localizedName(language: language).nonEmpty,
            assignment.studentName.nonEmpty,
            assignment.programName.nonEmpty,
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
        .nonEmpty ?? annualReportText(language, english: "Teaching assignment", swedish: "Undervisningsuppdrag")
    }

    private func annualReportDateRange(from: String, to: String, language: AppLanguage) -> String {
        switch (from.nonEmpty, to.nonEmpty) {
        case let (.some(from), .some(to)) where from != to:
            if let fromDate = DateParsers.isoDay.date(from: from),
               let toDate = DateParsers.isoDay.date(from: to) {
                return annualReportFormattedDateRange(from: fromDate, to: toDate, language: language)
            }
            return "\(annualReportDisplayDate(from, language: language))-\(annualReportDisplayDate(to, language: language))"
        case let (.some(from), _):
            return annualReportDisplayDate(from, language: language)
        case let (_, .some(to)):
            return annualReportDisplayDate(to, language: language)
        default:
            return "–"
        }
    }

    private func annualReportTeachingDetailDateRange(from rawFrom: String, to rawTo: String, year: Int, language: AppLanguage) -> String {
        let calendar = Calendar.current
        guard let yearStart = DateComponents(calendar: calendar, year: year, month: 1, day: 1).date,
              let yearEnd = DateComponents(calendar: calendar, year: year, month: 12, day: 31).date else {
            return annualReportDateRange(from: rawFrom, to: rawTo, language: language)
        }
        let fromDate = rawFrom.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        let toDate = rawTo.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        guard let start = fromDate ?? toDate else {
            return annualReportDateRange(from: rawFrom, to: rawTo, language: language)
        }
        let today = calendar.startOfDay(for: Date())
        let rawEnd = toDate ?? (start <= today ? today : start)
        let lower = min(start, rawEnd)
        let upper = max(start, rawEnd)
        let visibleStart = max(lower, yearStart)
        let visibleEnd = min(upper, yearEnd)
        guard visibleStart <= visibleEnd else {
            return annualReportDateRange(from: rawFrom, to: rawTo, language: language)
        }
        return annualReportDateRange(
            from: DateParsers.isoDay.string(from: visibleStart),
            to: DateParsers.isoDay.string(from: visibleEnd),
            language: language
        )
    }

    private func annualReportDisplayDate(_ raw: String?, language: AppLanguage) -> String {
        guard let value = raw?.trimmedOrNil else { return "–" }
        if let date = DateParsers.isoDay.date(from: value) {
            return annualReportDateText(date, language: language)
        }
        if Int(value) != nil {
            return annualReportText(language, english: "During the year", swedish: "Under året")
        }
        return value
    }

    private func annualReportFormattedDateRange(from: Date, to: Date, language: AppLanguage) -> String {
        let calendar = Calendar.current
        let fromComponents = calendar.dateComponents([.year, .month, .day], from: from)
        let toComponents = calendar.dateComponents([.year, .month, .day], from: to)
        guard let fromDay = fromComponents.day,
              let fromMonth = fromComponents.month,
              let toDay = toComponents.day,
              let toMonth = toComponents.month else {
            return "\(annualReportDateText(from, language: language))-\(annualReportDateText(to, language: language))"
        }

        if fromComponents.year == toComponents.year, fromMonth == toMonth {
            if fromDay == toDay {
                return annualReportDateText(from, language: language)
            }
            let month = annualReportMonthName(fromMonth, language: language)
            return language == .swedish ? "\(fromDay)-\(toDay) \(month)" : "\(month) \(fromDay)-\(toDay)"
        }

        return "\(annualReportDateText(from, language: language))-\(annualReportDateText(to, language: language))"
    }

    private func annualReportDateText(_ date: Date, language: AppLanguage) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let day = components.day, let month = components.month else {
            return DateParsers.isoDay.string(from: date)
        }
        let monthName = annualReportMonthName(month, language: language)
        return language == .swedish ? "\(day) \(monthName)" : "\(monthName) \(day)"
    }

    private func annualReportMonthName(_ month: Int, language: AppLanguage) -> String {
        let swedishMonths = ["jan", "feb", "mars", "apr", "maj", "juni", "juli", "aug", "sep", "okt", "nov", "dec"]
        let englishMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let months = language == .swedish ? swedishMonths : englishMonths
        guard (1...months.count).contains(month) else { return "" }
        return months[month - 1]
    }

    private func annualReportTeachingHours(year: Int) -> AnnualReportTeachingHours {
        let contextsByID = Dictionary(uniqueKeysWithValues: teachingCourses.map { ($0.id, $0) })
        let doctoralSourceAssignmentIDs = Set(doctoralCandidates.flatMap(\.sourceAssignmentIDs))
        var result = AnnualReportTeachingHours()

        for assignment in teachingAssignments where !doctoralSourceAssignmentIDs.contains(assignment.id) {
            let context = assignment.contextID.flatMap { contextsByID[$0] }
            let isDoctoralReport =
                assignment.reportCategory == .doctoralCourseTeaching ||
                assignment.reportCategory == .doctoralPrincipalSupervision ||
                assignment.reportCategory == .doctoralAssistantSupervision
            let isDoctoral = isDoctoralReport || context?.level == .doctoral || context?.contextType == .doctoralEducation
            let isClinical = context?.contextType == .clinicalTeaching
            let hours = annualReportAssignmentHours(assignment, year: year)

            if isDoctoral {
                result.doctoral += hours
            } else if isClinical {
                result.clinical += hours
            } else {
                result.other += hours
            }
        }

        for candidate in doctoralCandidates {
            result.doctoral += annualReportDoctoralCandidateHours(candidate, year: year)
        }

        return result
    }

    private func annualReportAssignmentHours(_ assignment: TeachingAssignment, year: Int) -> Double {
        assignment.periods.reduce(0) { partial, period in
            guard !period.isEmpty,
                  let hoursPerTerm = GrantParsing.numericValue(from: period.hoursPerTerm),
                  hoursPerTerm > 0 else {
                return partial
            }
            let terms = annualReportTeachingTerms(from: period.from, to: period.to)
            let matchingTermCount = terms.filter { $0.year == year }.count
            return partial + (Double(matchingTermCount) * hoursPerTerm)
        }
    }

    private func annualReportDoctoralCandidateHours(_ candidate: DoctoralCandidateRecord, year: Int) -> Double {
        // Round 12: hours in proportion to days (one rule everywhere).
        candidate.supervisionPeriods
            .filter { !$0.isEmpty }
            .reduce(0) { $0 + $1.supervisionHours(inYear: year, untilReferenceDate: false) }
    }

    private func annualReportTeachingTerms(from rawFrom: String, to rawTo: String) -> Set<AnnualReportTeachingTerm> {
        let fromDate = rawFrom.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        let toDate = rawTo.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        guard let start = fromDate ?? toDate else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        let end = toDate ?? (start <= today ? today : start)
        let lower = min(start, end)
        let upper = max(start, end)
        var cursor = lower
        var terms = Set<AnnualReportTeachingTerm>()

        while cursor <= upper {
            terms.insert(AnnualReportTeachingTerm(date: cursor))
            guard let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = nextMonth
        }
        terms.insert(AnnualReportTeachingTerm(date: upper))
        return terms
    }

    private func annualReportCurrentUserPublications() -> [PublicationRecord] {
        // F13d: the researcher link first, the written name as fallback.
        publications.filter { publication in
            isCurrentUserAmong(ids: publication.authorIDs, names: publication.authorNames)
        }
    }

    private func annualReportCurrentUserGrantApplications() -> [GrantApplication] {
        applications.filter { application in
            isCurrentUserAmong(ids: application.coApplicantAuthorIDs, names: application.coApplicants)
        }
    }

    private func annualReportCurrentUserIsFirstApplicant(_ application: GrantApplication) -> Bool {
        isCurrentUserFirstPerson(ids: application.coApplicantAuthorIDs, names: application.coApplicants)
    }

    private func annualReportPublicationTypeBucket(_ publication: PublicationRecord) -> String {
        let type = publication.publicationType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type == "protocol" || type == "protocol article" || type == "research letter" {
            return "other"
        }
        if type.contains("review") {
            return "review"
        }
        return "original"
    }

    private func annualReportPublicationStatusYear(_ publication: PublicationRecord) -> Int? {
        publication.statusDate?.nonEmpty.flatMap(annualReportYearValue)
            ?? publication.currentSubmissionDate?.nonEmpty.flatMap(annualReportYearValue)
            ?? publication.yearValue
    }

    private func annualReportJIFValue(_ publication: PublicationRecord) -> Double? {
        guard let journal = linkedJournal(of: publication),
              let metric = journal.preferredMetric(
                for: [.clarivateScieJIF, .clarivateEsciJIF],
                publicationYear: publication.yearValue
              ) else {
            return nil
        }
        return Double(metric.value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private func annualReportGrantStatus(_ application: GrantApplication) -> AnnualReportGrantStatus? {
        switch application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Väntar svar":
            return .waiting
        case "Beviljat":
            return .granted
        case "Avslag":
            return .rejected
        default:
            return nil
        }
    }

    private func annualReportGrantAmount(_ application: GrantApplication) -> Double {
        let amount: Double
        if application.isGranted {
            amount = application.grantedAmountValue ?? application.appliedAmountValue ?? application.preferredBudgetAmountValue ?? 0
        } else {
            amount = application.appliedAmountValue ?? application.preferredBudgetAmountValue ?? 0
        }
        return approximateSEKValue(amount, for: application) ?? amount
    }

    private func annualReportYearValue(_ raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let value = Int(raw) {
            return value
        }
        if let date = DateParsers.isoDay.date(from: raw) {
            return Calendar.current.component(.year, from: date)
        }
        return nil
    }

    private func annualReportCurrencyText(_ value: Double, language: AppLanguage) -> String {
        guard value > 0 else { return "–" }
        let millions = value / 1_000_000
        return "\(annualReportDecimalText(millions, language: language)) \(annualReportText(language, english: "MSEK", swedish: "mkr"))"
    }

    private func annualReportSEKAmountText(_ value: Double, language: AppLanguage) -> String {
        guard value > 0 else { return "–" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language == .swedish ? "sv_SE" : "en_US")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value.rounded()))"
    }

    private func annualReportHoursText(_ value: Double, language: AppLanguage) -> String {
        "\(annualReportDecimalText(value, language: language)) h"
    }

    private func annualReportOptionalDecimalText(_ value: Double?, language: AppLanguage) -> String {
        guard let value else { return "–" }
        return annualReportDecimalText(value, language: language)
    }

    private func annualReportDecimalText(_ value: Double, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language == .swedish ? "sv_SE" : "en_US")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = abs(value) >= 10 || value.rounded() == value ? 0 : 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func annualReportText(_ language: AppLanguage, english: String, swedish: String) -> String {
        language == .swedish ? swedish : english
    }
}

private struct AnnualReportTeachingTerm: Hashable {
    let year: Int
    let half: Int

    init(date: Date) {
        let calendar = Calendar.current
        year = calendar.component(.year, from: date)
        half = calendar.component(.month, from: date) <= 6 ? 1 : 2
    }
}
