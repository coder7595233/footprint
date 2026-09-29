import Foundation

func normalizedOrganizationCongressRows(_ congresses: [OrganizationCongress]) -> [OrganizationCongress] {
    var normalized = persistedOrganizationCongresses(from: congresses)
    normalized.append(OrganizationCongress())
    return normalized
}

func persistedOrganizationCongresses(from congresses: [OrganizationCongress]) -> [OrganizationCongress] {
    let normalized = congresses.enumerated().compactMap { offset, congress -> (offset: Int, congress: OrganizationCongress)? in
        let normalizedFrom = DateParsers.canonicalizedDayInput(congress.from)
        let normalizedTo = DateParsers.canonicalizedDayInput(congress.to)
        let normalizedAbstractDeadline = DateParsers.canonicalizedDayInput(congress.abstractSubmissionDeadline)
        let normalizedLateDeadline = DateParsers.canonicalizedDayInput(congress.lateAbstractSubmissionDeadline)
        let normalizedFlights = persistedOrganizationCongressFlights(from: congress.travelFlights)
        let normalizedHotels = persistedOrganizationCongressHotels(from: organizationCongressHotelsForPersistence(congress))
        let primaryHotel = normalizedHotels.first
        let normalizedFundingApplicationIDs = Array(
            NSOrderedSet(array: congress.fundingApplicationIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? congress.fundingApplicationIDs.compactMap(\.trimmedOrNil)
        let normalizedParticipantNames = Array(
            NSOrderedSet(array: congress.participantNames.compactMap(\.trimmedOrNil))
        ) as? [String] ?? congress.participantNames.compactMap(\.trimmedOrNil)
        let normalizedParticipantAuthorIDs = Array(
            NSOrderedSet(array: congress.participantAuthorIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? congress.participantAuthorIDs.compactMap(\.trimmedOrNil)
        let normalizedTasks = persistedOrganizationCongressTasks(from: congress.tasks)
        let trimmed = OrganizationCongress(
            id: congress.id.trimmingCharacters(in: .whitespacesAndNewlines),
            title: congress.title.trimmingCharacters(in: .whitespacesAndNewlines),
            from: normalizedFrom,
            fromUncertain: normalizedFrom.trimmedOrNil == nil ? false : congress.fromUncertain,
            to: normalizedTo,
            toUncertain: normalizedTo.trimmedOrNil == nil ? false : congress.toUncertain,
            abstractSubmissionDeadline: normalizedAbstractDeadline,
            abstractSubmissionDeadlineUncertain: normalizedAbstractDeadline.trimmedOrNil == nil ? false : congress.abstractSubmissionDeadlineUncertain,
            lateAbstractSubmissionDeadline: normalizedLateDeadline,
            lateAbstractSubmissionDeadlineUncertain: normalizedLateDeadline.trimmedOrNil == nil ? false : congress.lateAbstractSubmissionDeadlineUncertain,
            venue: congress.venue.trimmingCharacters(in: .whitespacesAndNewlines),
            city: congress.city.trimmingCharacters(in: .whitespacesAndNewlines),
            country: congress.country.trimmingCharacters(in: .whitespacesAndNewlines),
            link: congress.link.trimmingCharacters(in: .whitespacesAndNewlines),
            participantNames: normalizedParticipantNames,
            participantAuthorIDs: normalizedParticipantAuthorIDs,
            isHiddenOnMap: congress.isHiddenOnMap,
            travelFlights: normalizedFlights,
            travelHotels: normalizedHotels,
            hotelName: primaryHotel?.hotelName ?? "",
            hotelFrom: primaryHotel?.fromDate ?? "",
            hotelFromTime: primaryHotel?.fromTime ?? "",
            hotelTo: primaryHotel?.toDate ?? "",
            hotelToTime: primaryHotel?.toTime ?? "",
            congressFeeSEK: congress.congressFeeSEK.trimmingCharacters(in: .whitespacesAndNewlines),
            congressFeePaid: congress.congressFeePaid,
            fundingApplicationIDs: normalizedFundingApplicationIDs,
            tasks: normalizedTasks,
            isEditingLocked: congress.isEditingLocked
        )
        guard !trimmed.isEmpty else { return nil }
        return (offset, trimmed)
    }
    .sorted { left, right in
        if organizationCongressSortOrder(left.congress, right.congress) {
            return true
        }
        if organizationCongressSortOrder(right.congress, left.congress) {
            return false
        }
        return left.offset < right.offset
    }

    var usedIDs = Set<String>()
    return normalized.map { entry in
        let uniqueID = uniqueOrganizationCongressID(for: entry.congress.id, usedIDs: &usedIDs)
        return OrganizationCongress(
            id: uniqueID,
            title: entry.congress.title,
            from: entry.congress.from,
            fromUncertain: entry.congress.fromUncertain,
            to: entry.congress.to,
            toUncertain: entry.congress.toUncertain,
            abstractSubmissionDeadline: entry.congress.abstractSubmissionDeadline,
            abstractSubmissionDeadlineUncertain: entry.congress.abstractSubmissionDeadlineUncertain,
            lateAbstractSubmissionDeadline: entry.congress.lateAbstractSubmissionDeadline,
            lateAbstractSubmissionDeadlineUncertain: entry.congress.lateAbstractSubmissionDeadlineUncertain,
            venue: entry.congress.venue,
            city: entry.congress.city,
            country: entry.congress.country,
            link: entry.congress.link,
            participantNames: entry.congress.participantNames,
            participantAuthorIDs: entry.congress.participantAuthorIDs,
            isHiddenOnMap: entry.congress.isHiddenOnMap,
            travelFlights: entry.congress.travelFlights,
            travelHotels: entry.congress.travelHotels,
            hotelName: entry.congress.hotelName,
            hotelFrom: entry.congress.hotelFrom,
            hotelFromTime: entry.congress.hotelFromTime,
            hotelTo: entry.congress.hotelTo,
            hotelToTime: entry.congress.hotelToTime,
            congressFeeSEK: entry.congress.congressFeeSEK,
            congressFeePaid: entry.congress.congressFeePaid,
            fundingApplicationIDs: entry.congress.fundingApplicationIDs,
            tasks: entry.congress.tasks,
            isEditingLocked: entry.congress.isEditingLocked
        )
    }
}

func persistedOrganizationCongressTasks(from tasks: [ProjectTaskItem]) -> [ProjectTaskItem] {
    tasks.compactMap { task in
        var normalized = task
        normalized.normalize()
        return normalized.isEmpty ? nil : normalized
    }
}

func organizationCongressHotelsForPersistence(_ congress: OrganizationCongress) -> [OrganizationCongressHotel] {
    let existingHotels = congress.travelHotels.filter { !$0.isEmpty }
    if !existingHotels.isEmpty {
        return existingHotels
    }
    let legacyHotel = OrganizationCongressHotel(
        id: "primary",
        hotelName: congress.hotelName,
        fromDate: congress.hotelFrom,
        fromTime: congress.hotelFromTime,
        toDate: congress.hotelTo,
        toTime: congress.hotelToTime
    )
    return legacyHotel.isEmpty ? [] : [legacyHotel]
}

func organizationCongressClearingCalendarOwnedPlanning(_ congress: OrganizationCongress) -> OrganizationCongress {
    var normalized = congress
    normalized.travelFlights = []
    normalized.travelHotels = []
    normalized.hotelName = ""
    normalized.hotelFrom = ""
    normalized.hotelFromTime = ""
    normalized.hotelTo = ""
    normalized.hotelToTime = ""
    return normalized
}

func organizationCongressesClearingCalendarOwnedPlanning(_ congresses: [OrganizationCongress]) -> [OrganizationCongress] {
    persistedOrganizationCongresses(from: congresses).map(organizationCongressClearingCalendarOwnedPlanning)
}

func persistedOrganizationCongressFlights(from flights: [OrganizationCongressFlight]) -> [OrganizationCongressFlight] {
    flights.compactMap { flight in
        var normalized = flight
        normalized.normalize()
        return normalized.isEmpty ? nil : normalized
    }
}

func persistedOrganizationCongressHotels(from hotels: [OrganizationCongressHotel]) -> [OrganizationCongressHotel] {
    hotels.compactMap { hotel in
        var normalized = hotel
        normalized.normalize()
        return normalized.isEmpty ? nil : normalized
    }
}

func organizationCongressRowsRemovingFirstMatch(id: String, from congresses: [OrganizationCongress]) -> [OrganizationCongress] {
    var remaining = congresses
    if let index = remaining.firstIndex(where: { $0.id == id }) {
        remaining.remove(at: index)
    }
    return normalizedOrganizationCongressRows(remaining)
}

private func uniqueOrganizationCongressID(for rawID: String, usedIDs: inout Set<String>) -> String {
    let trimmedID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedID.isEmpty {
        return unusedOrganizationCongressUUID(usedIDs: &usedIDs)
    }
    let baseID = trimmedID
    if !usedIDs.contains(baseID) {
        usedIDs.insert(baseID)
        return baseID
    }
    if UUID(uuidString: baseID) != nil {
        return unusedOrganizationCongressUUID(usedIDs: &usedIDs)
    }

    var counter = 2
    while true {
        let candidate = "\(baseID)-\(counter)"
        if !usedIDs.contains(candidate) {
            usedIDs.insert(candidate)
            return candidate
        }
        counter += 1
    }
}

private func unusedOrganizationCongressUUID(usedIDs: inout Set<String>) -> String {
    var candidate = UUID().uuidString
    while usedIDs.contains(candidate) {
        candidate = UUID().uuidString
    }
    usedIDs.insert(candidate)
    return candidate
}

private func organizationCongressSortOrder(_ lhs: OrganizationCongress, _ rhs: OrganizationCongress) -> Bool {
    func primaryDate(for congress: OrganizationCongress) -> Date? {
        [
            congress.from,
            congress.to,
            congress.abstractSubmissionDeadline,
            congress.lateAbstractSubmissionDeadline
        ]
        .compactMap { DateParsers.isoDay.date(from: $0) }
        .first
    }

    let leftDate = primaryDate(for: lhs)
    let rightDate = primaryDate(for: rhs)
    switch (leftDate, rightDate) {
    case let (left?, right?):
        if left != right {
            return left < right
        }
    case (.some, nil):
        return true
    case (nil, .some):
        return false
    case (nil, nil):
        break
    }

    let leftTitle = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let rightTitle = rhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let comparison = leftTitle.localizedStandardCompare(rightTitle)
    if comparison != .orderedSame {
        return comparison == .orderedAscending
    }
    return lhs.id < rhs.id
}
