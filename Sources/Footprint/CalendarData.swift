import Foundation

enum CalendarWeekdayChoice: String, CaseIterable, Codable, Hashable, Identifiable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: String { rawValue }

    var calendarWeekday: Int {
        switch self {
        case .sunday:
            return 1
        case .monday:
            return 2
        case .tuesday:
            return 3
        case .wednesday:
            return 4
        case .thursday:
            return 5
        case .friday:
            return 6
        case .saturday:
            return 7
        }
    }

    func localizedName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.monday, .swedish):
            return "Måndag"
        case (.tuesday, .swedish):
            return "Tisdag"
        case (.wednesday, .swedish):
            return "Onsdag"
        case (.thursday, .swedish):
            return "Torsdag"
        case (.friday, .swedish):
            return "Fredag"
        case (.saturday, .swedish):
            return "Lördag"
        case (.sunday, .swedish):
            return "Söndag"
        case (.monday, .english):
            return "Monday"
        case (.tuesday, .english):
            return "Tuesday"
        case (.wednesday, .english):
            return "Wednesday"
        case (.thursday, .english):
            return "Thursday"
        case (.friday, .english):
            return "Friday"
        case (.saturday, .english):
            return "Saturday"
        case (.sunday, .english):
            return "Sunday"
        }
    }
}

enum CalendarCountryDisplayMode: String, CaseIterable, Codable, Hashable, Identifiable {
    case text
    case flags
    case hidden

    var id: String { rawValue }

    func localizedName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.text, .swedish):
            return "Text"
        case (.flags, .swedish):
            return "Flaggor"
        case (.hidden, .swedish):
            return "Visa inte"
        case (.text, .english):
            return "Text"
        case (.flags, .english):
            return "Flags"
        case (.hidden, .english):
            return "Hide"
        }
    }
}

enum CalendarTravelMode: String, CaseIterable, Codable, Hashable, Identifiable {
    case flight
    case train
    case bus
    case car
    case boat

    var id: String { rawValue }

    var calendarSystemImageName: String {
        switch self {
        case .flight:
            return "airplane"
        case .train:
            return "train.side.front.car"
        case .bus:
            return "bus"
        case .car:
            return "car"
        case .boat:
            return "ferry"
        }
    }

    func localizedName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.flight, .swedish):
            return "Flyg"
        case (.train, .swedish):
            return "Tåg"
        case (.bus, .swedish):
            return "Buss"
        case (.car, .swedish):
            return "Bil"
        case (.boat, .swedish):
            return "Båt"
        case (.flight, .english):
            return "Flight"
        case (.train, .english):
            return "Train"
        case (.bus, .english):
            return "Bus"
        case (.car, .english):
            return "Car"
        case (.boat, .english):
            return "Boat"
        }
    }
}

struct CalendarTravelRecord: Codable, Hashable, Identifiable {
    var id: String
    var date: String
    var arrivalDate: String
    var dateUncertain: Bool
    var departureTime: String
    var departureTimeUncertain: Bool
    var fromCity: String
    var fromCountry: String
    var arrivalTime: String
    var arrivalTimeUncertain: Bool
    var toCity: String
    var toCountry: String
    var mode: CalendarTravelMode
    var congressOrganizationID: String
    var congressID: String
    var reference: String

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case arrivalDate
        case dateUncertain
        case departureTime
        case departureTimeUncertain
        case fromCity
        case fromCountry
        case arrivalTime
        case arrivalTimeUncertain
        case toCity
        case toCountry
        case mode
        case congressOrganizationID
        case congressID
        case reference
    }

    init(
        id: String = UUID().uuidString,
        date: String = "",
        arrivalDate: String = "",
        dateUncertain: Bool = false,
        departureTime: String = "",
        departureTimeUncertain: Bool = false,
        fromCity: String = "",
        fromCountry: String = "",
        arrivalTime: String = "",
        arrivalTimeUncertain: Bool = false,
        toCity: String = "",
        toCountry: String = "",
        mode: CalendarTravelMode = .flight,
        congressOrganizationID: String = "",
        congressID: String = "",
        reference: String = ""
    ) {
        self.id = id
        self.date = date
        self.arrivalDate = arrivalDate
        self.dateUncertain = dateUncertain
        self.departureTime = departureTime
        self.departureTimeUncertain = departureTimeUncertain
        self.fromCity = fromCity
        self.fromCountry = fromCountry
        self.arrivalTime = arrivalTime
        self.arrivalTimeUncertain = arrivalTimeUncertain
        self.toCity = toCity
        self.toCountry = toCountry
        self.mode = mode
        self.congressOrganizationID = congressOrganizationID
        self.congressID = congressID
        self.reference = reference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        arrivalDate = try container.decodeIfPresent(String.self, forKey: .arrivalDate) ?? ""
        dateUncertain = try container.decodeIfPresent(Bool.self, forKey: .dateUncertain) ?? false
        departureTime = try container.decodeIfPresent(String.self, forKey: .departureTime) ?? ""
        departureTimeUncertain = try container.decodeIfPresent(Bool.self, forKey: .departureTimeUncertain) ?? false
        fromCity = try container.decodeIfPresent(String.self, forKey: .fromCity) ?? ""
        fromCountry = try container.decodeIfPresent(String.self, forKey: .fromCountry) ?? ""
        arrivalTime = try container.decodeIfPresent(String.self, forKey: .arrivalTime) ?? ""
        arrivalTimeUncertain = try container.decodeIfPresent(Bool.self, forKey: .arrivalTimeUncertain) ?? false
        toCity = try container.decodeIfPresent(String.self, forKey: .toCity) ?? ""
        toCountry = try container.decodeIfPresent(String.self, forKey: .toCountry) ?? ""
        mode = try container.decodeIfPresent(CalendarTravelMode.self, forKey: .mode) ?? .flight
        congressOrganizationID = try container.decodeIfPresent(String.self, forKey: .congressOrganizationID) ?? ""
        congressID = try container.decodeIfPresent(String.self, forKey: .congressID) ?? ""
        reference = try container.decodeIfPresent(String.self, forKey: .reference) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(arrivalDate, forKey: .arrivalDate)
        try container.encode(dateUncertain, forKey: .dateUncertain)
        try container.encode(departureTime, forKey: .departureTime)
        try container.encode(departureTimeUncertain, forKey: .departureTimeUncertain)
        try container.encode(fromCity, forKey: .fromCity)
        try container.encode(fromCountry, forKey: .fromCountry)
        try container.encode(arrivalTime, forKey: .arrivalTime)
        try container.encode(arrivalTimeUncertain, forKey: .arrivalTimeUncertain)
        try container.encode(toCity, forKey: .toCity)
        try container.encode(toCountry, forKey: .toCountry)
        try container.encode(mode, forKey: .mode)
        if !congressOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(congressOrganizationID, forKey: .congressOrganizationID)
        }
        if !congressID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(congressID, forKey: .congressID)
        }
        try container.encode(reference, forKey: .reference)
    }

    mutating func normalize() {
        date = DateParsers.canonicalizedDayInput(date)
        arrivalDate = DateParsers.canonicalizedDayInput(arrivalDate)
        departureTime = normalizedCalendarTimeInput(departureTime)
        arrivalTime = normalizedCalendarTimeInput(arrivalTime)
        fromCity = fromCity.trimmingCharacters(in: .whitespacesAndNewlines)
        fromCountry = fromCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        toCity = toCity.trimmingCharacters(in: .whitespacesAndNewlines)
        toCountry = toCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        congressOrganizationID = congressOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        congressID = congressID.trimmingCharacters(in: .whitespacesAndNewlines)
        if congressOrganizationID.isEmpty || congressID.isEmpty {
            congressOrganizationID = ""
            congressID = ""
        }
        if fromCountry.trimmedOrNil == nil {
            let split = splitLegacyCalendarMeetingPlace(fromCity)
            if split.country.trimmedOrNil != nil {
                fromCity = split.place
                fromCountry = split.country
            }
        }
        if toCountry.trimmedOrNil == nil {
            let split = splitLegacyCalendarMeetingPlace(toCity)
            if split.country.trimmedOrNil != nil {
                toCity = split.place
                toCountry = split.country
            }
        }
        reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if date.trimmedOrNil == nil {
            arrivalDate = ""
            dateUncertain = false
        } else {
            if arrivalDate.trimmedOrNil == nil {
                arrivalDate = derivedArrivalDateString()
            }
        }
        departureTimeUncertain = departureTime.trimmedOrNil == nil ? false : departureTimeUncertain
        arrivalTimeUncertain = arrivalTime.trimmedOrNil == nil ? false : arrivalTimeUncertain
    }

    func derivedArrivalDateString() -> String {
        guard let startDate = DateParsers.isoDay.date(from: date) else { return "" }
        guard let departure = departureTime.trimmedOrNil,
              let arrival = arrivalTime.trimmedOrNil else {
            return date
        }
        if arrival.localizedStandardCompare(departure) == .orderedAscending,
           let nextDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startDate) {
            return DateParsers.isoDay.string(from: nextDate)
        }
        return date
    }

    func resolvedArrivalDateString() -> String {
        arrivalDate.trimmedOrNil ?? derivedArrivalDateString()
    }

    func resolvedArrivalDateTime(calendar: Calendar) -> Date? {
        guard let day = DateParsers.isoDay.date(from: resolvedArrivalDateString()) else {
            return nil
        }
        let startOfDay = calendar.startOfDay(for: day)
        let minutes = calendarTravelSortMinutes(arrivalTime)
            ?? calendarTravelSortMinutes(departureTime)
            ?? ((24 * 60) - 1)
        return calendar.date(byAdding: .minute, value: minutes, to: startOfDay)
    }

    var isEmpty: Bool {
        date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && arrivalDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && departureTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fromCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fromCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && arrivalTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && toCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && toCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct CalendarAccommodationRecord: Codable, Hashable, Identifiable {
    var id: String
    var hotelName: String
    var checkInDate: String
    var checkInTime: String
    var checkOutDate: String
    var checkOutTime: String
    var city: String
    var country: String
    var congressOrganizationID: String
    var congressID: String
    var reference: String

    enum CodingKeys: String, CodingKey {
        case id
        case hotelName
        case checkInDate
        case checkInTime
        case checkOutDate
        case checkOutTime
        case city
        case country
        case congressOrganizationID
        case congressID
        case reference
    }

    init(
        id: String = UUID().uuidString,
        hotelName: String = "",
        checkInDate: String = "",
        checkInTime: String = "",
        checkOutDate: String = "",
        checkOutTime: String = "",
        city: String = "",
        country: String = "",
        congressOrganizationID: String = "",
        congressID: String = "",
        reference: String = ""
    ) {
        self.id = id
        self.hotelName = hotelName
        self.checkInDate = checkInDate
        self.checkInTime = checkInTime
        self.checkOutDate = checkOutDate
        self.checkOutTime = checkOutTime
        self.city = city
        self.country = country
        self.congressOrganizationID = congressOrganizationID
        self.congressID = congressID
        self.reference = reference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        hotelName = try container.decodeIfPresent(String.self, forKey: .hotelName) ?? ""
        checkInDate = try container.decodeIfPresent(String.self, forKey: .checkInDate) ?? ""
        checkInTime = try container.decodeIfPresent(String.self, forKey: .checkInTime) ?? ""
        checkOutDate = try container.decodeIfPresent(String.self, forKey: .checkOutDate) ?? ""
        checkOutTime = try container.decodeIfPresent(String.self, forKey: .checkOutTime) ?? ""
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        congressOrganizationID = try container.decodeIfPresent(String.self, forKey: .congressOrganizationID) ?? ""
        congressID = try container.decodeIfPresent(String.self, forKey: .congressID) ?? ""
        reference = try container.decodeIfPresent(String.self, forKey: .reference) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hotelName, forKey: .hotelName)
        try container.encode(checkInDate, forKey: .checkInDate)
        try container.encode(checkInTime, forKey: .checkInTime)
        try container.encode(checkOutDate, forKey: .checkOutDate)
        try container.encode(checkOutTime, forKey: .checkOutTime)
        try container.encode(city, forKey: .city)
        try container.encode(country, forKey: .country)
        if !congressOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(congressOrganizationID, forKey: .congressOrganizationID)
        }
        if !congressID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try container.encode(congressID, forKey: .congressID)
        }
        try container.encode(reference, forKey: .reference)
    }

    mutating func normalize() {
        hotelName = hotelName.trimmingCharacters(in: .whitespacesAndNewlines)
        checkInDate = DateParsers.canonicalizedDayInput(checkInDate)
        checkInTime = normalizedCalendarTimeInput(checkInTime)
        checkOutDate = DateParsers.canonicalizedDayInput(checkOutDate)
        checkOutTime = normalizedCalendarTimeInput(checkOutTime)
        city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        congressOrganizationID = congressOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        congressID = congressID.trimmingCharacters(in: .whitespacesAndNewlines)
        reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)

        if congressOrganizationID.isEmpty || congressID.isEmpty {
            congressOrganizationID = ""
            congressID = ""
        }
        if country.trimmedOrNil == nil {
            let split = splitLegacyCalendarMeetingPlace(city)
            if split.country.trimmedOrNil != nil {
                city = split.place
                country = split.country
            }
        }
        if checkInDate.trimmedOrNil == nil, checkOutDate.trimmedOrNil != nil {
            checkInDate = checkOutDate
        }
        if checkOutDate.trimmedOrNil == nil, checkInDate.trimmedOrNil != nil {
            checkOutDate = checkInDate
        }
        if let checkIn = DateParsers.isoDay.date(from: checkInDate),
           let checkOut = DateParsers.isoDay.date(from: checkOutDate),
           checkOut < checkIn {
            swap(&checkInDate, &checkOutDate)
            swap(&checkInTime, &checkOutTime)
        }
    }

    var isEmpty: Bool {
        hotelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && checkInDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && checkInTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && checkOutDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && checkOutTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct CalendarVerticalNoteRecord: Codable, Hashable, Identifiable {
    var id: String
    var text: String
    var startDate: String
    var endDate: String

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case startDate
        case endDate
    }

    init(
        id: String = UUID().uuidString,
        text: String = "",
        startDate: String = "",
        endDate: String = ""
    ) {
        self.id = id
        self.text = text
        self.startDate = startDate
        self.endDate = endDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
    }

    mutating func normalize() {
        id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            id = UUID().uuidString
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        startDate = DateParsers.canonicalizedDayInput(startDate)
        endDate = DateParsers.canonicalizedDayInput(endDate)
        if startDate.trimmedOrNil == nil, endDate.trimmedOrNil != nil {
            startDate = endDate
        }
        if endDate.trimmedOrNil == nil, startDate.trimmedOrNil != nil {
            endDate = startDate
        }
        if let start = DateParsers.isoDay.date(from: startDate),
           let end = DateParsers.isoDay.date(from: endDate),
           end < start {
            swap(&startDate, &endDate)
        }
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && startDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func includes(_ date: Date, calendar: Calendar) -> Bool {
        guard let start = DateParsers.isoDay.date(from: startDate),
              let end = DateParsers.isoDay.date(from: endDate) else {
            return false
        }
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }
}

func calendarTravelLocationSort(
    _ lhs: CalendarTravelRecord,
    _ rhs: CalendarTravelRecord,
    calendar: Calendar
) -> Bool {
    let leftArrival = lhs.resolvedArrivalDateTime(calendar: calendar)
    let rightArrival = rhs.resolvedArrivalDateTime(calendar: calendar)
    switch (leftArrival, rightArrival) {
    case let (left?, right?) where left != right:
        return left < right
    case (.some, nil):
        return true
    case (nil, .some):
        return false
    default:
        break
    }

    let leftDeparture = calendarTravelDepartureDateTime(lhs, calendar: calendar)
    let rightDeparture = calendarTravelDepartureDateTime(rhs, calendar: calendar)
    switch (leftDeparture, rightDeparture) {
    case let (left?, right?) where left != right:
        return left < right
    case (.some, nil):
        return true
    case (nil, .some):
        return false
    default:
        return lhs.id < rhs.id
    }
}

func calendarAccommodationSort(
    _ lhs: CalendarAccommodationRecord,
    _ rhs: CalendarAccommodationRecord
) -> Bool {
    let leftDate = DateParsers.isoDay.date(from: lhs.checkInDate) ?? .distantFuture
    let rightDate = DateParsers.isoDay.date(from: rhs.checkInDate) ?? .distantFuture
    if leftDate != rightDate {
        return leftDate < rightDate
    }
    if lhs.checkInTime != rhs.checkInTime {
        return lhs.checkInTime.localizedStandardCompare(rhs.checkInTime) == .orderedAscending
    }
    let nameComparison = lhs.hotelName.localizedStandardCompare(rhs.hotelName)
    if nameComparison != .orderedSame {
        return nameComparison == .orderedAscending
    }
    return lhs.id < rhs.id
}

private func calendarTravelDepartureDateTime(_ record: CalendarTravelRecord, calendar: Calendar) -> Date? {
    guard let day = DateParsers.isoDay.date(from: record.date) else {
        return nil
    }
    let startOfDay = calendar.startOfDay(for: day)
    let minutes = calendarTravelSortMinutes(record.departureTime) ?? 0
    return calendar.date(byAdding: .minute, value: minutes, to: startOfDay)
}

private func calendarTravelSortMinutes(_ raw: String) -> Int? {
    let normalized = normalizedCalendarTimeInput(raw).trimmedOrNil
    guard let normalized else { return nil }
    let parts = normalized.split(separator: ":", maxSplits: 1)
    guard parts.count == 2,
          let hours = Int(parts[0]),
          let minutes = Int(parts[1]),
          (0..<24).contains(hours),
          (0..<60).contains(minutes) else {
        return nil
    }
    return hours * 60 + minutes
}

private func calendarFlagText(for countryName: String) -> String? {
    let trimmed = GrantParsing.canonicalCountryName(countryName).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("Somaliland") != .orderedSame else { return nil }

    let explicitCodes: [String: String] = [
        "Sweden": "SE", "Sverige": "SE",
        "United Kingdom": "GB", "UK": "GB", "U.K.": "GB", "England": "GB", "Storbritannien": "GB",
        "Norway": "NO", "Norge": "NO",
        "Denmark": "DK", "Danmark": "DK",
        "Finland": "FI",
        "Germany": "DE", "Tyskland": "DE",
        "France": "FR", "Frankrike": "FR",
        "Netherlands": "NL", "Nederländerna": "NL",
        "Belgium": "BE", "Belgien": "BE",
        "Switzerland": "CH", "Schweiz": "CH",
        "Austria": "AT", "Österrike": "AT",
        "Italy": "IT", "Italien": "IT",
        "Spain": "ES", "Spanien": "ES",
        "Australia": "AU", "Australien": "AU",
        "United States": "US", "USA": "US", "Förenta staterna": "US"
    ]

    let uppercased = trimmed.uppercased()
    let regionCode =
        (uppercased.count == 2 ? uppercased : nil)
        ?? explicitCodes[trimmed]
        ?? Locale.Region.isoRegions.first(where: {
            let english = Locale(identifier: "en_US").localizedString(forRegionCode: $0.identifier)
            let swedish = Locale(identifier: "sv_SE").localizedString(forRegionCode: $0.identifier)
            return english == trimmed || swedish == trimmed
        })?.identifier

    guard let regionCode else { return nil }
    return regionCode
        .unicodeScalars
        .compactMap { UnicodeScalar(127397 + $0.value) }
        .map(String.init)
        .joined()
}

private let legacyCalendarPlaceCountryVariants: [(variant: String, canonical: String, isFlag: Bool)] = {
    let countries = GrantParsing.countryOptions.sorted { $0.count > $1.count }
    var rows: [(variant: String, canonical: String, isFlag: Bool)] = []
    var seen = Set<String>()

    for canonical in countries {
        let localizedSv = AppLanguage.swedish.localizedCountry(canonical)
        let localizedEn = AppLanguage.english.localizedCountry(canonical)
        let variants = [canonical, localizedSv, localizedEn] + [calendarFlagText(for: canonical)].compactMap { $0 }

        for variant in variants {
            let trimmed = variant.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = "\(canonical.lowercased())|\(trimmed.lowercased())"
            guard seen.insert(key).inserted else { continue }
            let isFlag = trimmed.unicodeScalars.allSatisfy { 127462...127487 ~= $0.value }
            rows.append((variant: trimmed, canonical: canonical, isFlag: isFlag))
        }
    }

    return rows.sorted { $0.variant.count > $1.variant.count }
}()

private let legacyCalendarPlaceFlagLookup: [String: String] = {
    Dictionary(
        uniqueKeysWithValues: legacyCalendarPlaceCountryVariants
            .filter(\.isFlag)
            .map { ($0.variant, $0.canonical) }
    )
}()

private let legacyCalendarPlaceTextLookup: [String: String] = {
    Dictionary(
        uniqueKeysWithValues: legacyCalendarPlaceCountryVariants
            .filter { !$0.isFlag }
            .map { ($0.variant.lowercased(), $0.canonical) }
    )
}()

private func splitLegacyCalendarMeetingPlace(_ raw: String) -> (place: String, country: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ("", "") }

    if trimmed.caseInsensitiveCompare("Online") == .orderedSame
        || trimmed.caseInsensitiveCompare("Telefon") == .orderedSame
        || trimmed.caseInsensitiveCompare("Phone") == .orderedSame {
        return (trimmed, "")
    }

    if let canonical = legacyCalendarPlaceFlagLookup[trimmed] {
        return ("", canonical)
    }
    if let canonical = legacyCalendarPlaceTextLookup[trimmed.lowercased()] {
        return ("", canonical)
    }
    if let lastSpace = trimmed.lastIndex(of: " ") {
        let suffix = String(trimmed[trimmed.index(after: lastSpace)...])
        let prefix = String(trimmed[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let canonical = legacyCalendarPlaceFlagLookup[suffix] {
            return (prefix, canonical)
        }
    } else {
        return (trimmed, "")
    }

    for entry in legacyCalendarPlaceCountryVariants {
        let variant = entry.variant
        if entry.isFlag {
            if trimmed == variant {
                return ("", entry.canonical)
            }
            if trimmed.hasSuffix(" \(variant)") {
                return (String(trimmed.dropLast(variant.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines), entry.canonical)
            }
        } else {
            if trimmed.caseInsensitiveCompare(variant) == .orderedSame {
                return ("", entry.canonical)
            }
            if trimmed.lowercased().hasSuffix(" \(variant.lowercased())") {
                return (String(trimmed.dropLast(variant.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines), entry.canonical)
            }
        }
    }

    return (trimmed, "")
}

enum CalendarMeetingMode: String, CaseIterable, Codable, Hashable, Identifiable {
    case online
    case physical
    case hybrid

    var id: String { rawValue }

    func localizedName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.online, .swedish):
            return "Online"
        case (.physical, .swedish):
            return "Fysiskt"
        case (.hybrid, .swedish):
            return "Hybrid"
        case (.online, .english):
            return "Online"
        case (.physical, .english):
            return "On-site"
        case (.hybrid, .english):
            return "Hybrid"
        }
    }
}

enum CalendarFixedCategory: String, CaseIterable, Codable, Hashable, Identifiable {
    case travel
    case task
    case deadline
    case uncategorized

    var id: String { rawValue }

    func localizedName(language: AppLanguage) -> String {
        switch self {
        case .travel:
            return language.text("Travel", "Resa")
        case .task:
            return language.text("Task", "Uppgift")
        case .deadline:
            return language.text("Deadlines", "Tidsfrister")
        case .uncategorized:
            return language.text("Uncategorized", "Ej kategoriserad")
        }
    }
}

enum CalendarActivityColorRole: String, CaseIterable, Codable, Hashable, Identifiable {
    case activity1
    case activity2
    case activity3
    case activity4

    var id: String { rawValue }

    func localizedName(language: AppLanguage) -> String {
        switch self {
        case .activity1:
            return language.text("Activity 1", "Aktivitet 1")
        case .activity2:
            return language.text("Activity 2", "Aktivitet 2")
        case .activity3:
            return language.text("Activity 3", "Aktivitet 3")
        case .activity4:
            return language.text("Activity 4", "Aktivitet 4")
        }
    }
}

func calendarMeetingCategoryDisplayName(_ raw: String, language: AppLanguage) -> String {
    raw.trimmedOrNil ?? CalendarFixedCategory.uncategorized.localizedName(language: language)
}

private let uncategorizedCalendarMeetingFilterKey = "__uncategorized__"

func calendarMeetingCategoryFilterKey(for raw: String) -> String {
    raw.trimmedOrNil.map(normalizedCalendarCategoryLookupKey) ?? uncategorizedCalendarMeetingFilterKey
}

func calendarMeetingCategoryFilterNames(from knownMeetingCategories: [String]) -> [String] {
    var names: [String] = [""]
    var seenKeys = Set([calendarMeetingCategoryFilterKey(for: "")])

    for name in knownMeetingCategories.compactMap(\.trimmedOrNil) {
        let key = calendarMeetingCategoryFilterKey(for: name)
        guard seenKeys.insert(key).inserted else { continue }
        names.append(name)
    }

    return names
}

enum CalendarDayHighlightKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case holiday
    case saturday
    case sunday

    var id: String { rawValue }

    func localizedName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.holiday, .swedish):
            return "Helgdagar"
        case (.saturday, .swedish):
            return "Lördagar"
        case (.sunday, .swedish):
            return "Söndagar"
        case (.holiday, .english):
            return "Holidays"
        case (.saturday, .english):
            return "Saturdays"
        case (.sunday, .english):
            return "Sundays"
        }
    }
}

struct CalendarDayHighlightColorSetting: Codable, Hashable, Identifiable {
    var id: String
    var lightTextHexColor: String
    var lightBackgroundHexColor: String
    var darkTextHexColor: String
    var darkBackgroundHexColor: String

    init(
        id: String,
        lightTextHexColor: String,
        lightBackgroundHexColor: String,
        darkTextHexColor: String? = nil,
        darkBackgroundHexColor: String? = nil
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lightTextHexColor = normalizedCalendarCategoryHexColor(lightTextHexColor)
        self.lightBackgroundHexColor = normalizedCalendarCategoryHexColor(lightBackgroundHexColor)
        self.darkTextHexColor = normalizedCalendarCategoryHexColor(darkTextHexColor ?? lightTextHexColor)
        self.darkBackgroundHexColor = normalizedCalendarCategoryHexColor(darkBackgroundHexColor ?? lightBackgroundHexColor)
    }

    mutating func normalize() {
        id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        lightTextHexColor = normalizedCalendarCategoryHexColor(lightTextHexColor)
        lightBackgroundHexColor = normalizedCalendarCategoryHexColor(lightBackgroundHexColor)
        darkTextHexColor = normalizedCalendarCategoryHexColor(darkTextHexColor, fallback: lightTextHexColor)
        darkBackgroundHexColor = normalizedCalendarCategoryHexColor(darkBackgroundHexColor, fallback: lightBackgroundHexColor)
    }

    func resolvedTextHexColor(usesDarkAppearance: Bool) -> String {
        usesDarkAppearance ? darkTextHexColor : lightTextHexColor
    }

    func resolvedBackgroundHexColor(usesDarkAppearance: Bool) -> String {
        usesDarkAppearance ? darkBackgroundHexColor : lightBackgroundHexColor
    }

    static func id(for kind: CalendarDayHighlightKind) -> String {
        kind.rawValue
    }
}

struct CalendarDayHighlightColorPreset: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var settings: [CalendarDayHighlightColorSetting]
}

struct CalendarCategoryColorSetting: Codable, Hashable, Identifiable {
    var id: String
    var lightHexColor: String
    var darkHexColor: String
    var colorSourceID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case lightHexColor
        case darkHexColor
        case colorSourceID
        case hexColor
    }

    init(id: String, lightHexColor: String, darkHexColor: String? = nil, colorSourceID: String? = nil) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lightHexColor = normalizedCalendarCategoryHexColor(lightHexColor)
        self.darkHexColor = normalizedCalendarCategoryHexColor(darkHexColor ?? lightHexColor)
        self.colorSourceID = colorSourceID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        let legacyHex = try container.decodeIfPresent(String.self, forKey: .hexColor)
        let decodedLight = try container.decodeIfPresent(String.self, forKey: .lightHexColor) ?? legacyHex ?? "#000000"
        let decodedDark = try container.decodeIfPresent(String.self, forKey: .darkHexColor) ?? decodedLight
        let decodedSourceID = try container.decodeIfPresent(String.self, forKey: .colorSourceID)
        self.init(id: decodedID, lightHexColor: decodedLight, darkHexColor: decodedDark, colorSourceID: decodedSourceID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(lightHexColor, forKey: .lightHexColor)
        try container.encode(darkHexColor, forKey: .darkHexColor)
        try container.encodeIfPresent(colorSourceID, forKey: .colorSourceID)
    }

    mutating func normalize() {
        id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        lightHexColor = normalizedCalendarCategoryHexColor(lightHexColor)
        darkHexColor = normalizedCalendarCategoryHexColor(darkHexColor, fallback: lightHexColor)
        colorSourceID = colorSourceID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    func resolvedHexColor(usesDarkAppearance: Bool) -> String {
        usesDarkAppearance ? darkHexColor : lightHexColor
    }

    static func fixedColorID(for category: CalendarFixedCategory) -> String {
        "fixed:\(category.rawValue)"
    }

    static func activityColorID(for role: CalendarActivityColorRole) -> String {
        "activity:\(role.rawValue)"
    }

    static let newActivityCategoryDefaultColorID = "template:new-activity-category"

    static func meetingColorID(for name: String) -> String {
        "meeting:\(normalizedCalendarCategoryLookupKey(name))"
    }
}

struct CalendarCategoryColorPreset: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var settings: [CalendarCategoryColorSetting]
}

func normalizedCalendarCategoryLookupKey(_ raw: String) -> String {
    raw
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sv_SE"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .lowercased()
}

func calendarMeetingCategoryUsageCount(in records: [CalendarMeetingRecord], named categoryName: String) -> Int {
    let lookupKey = normalizedCalendarCategoryLookupKey(categoryName)
    guard !lookupKey.isEmpty else { return 0 }
    return records.reduce(into: 0) { count, record in
        if normalizedCalendarCategoryLookupKey(record.meetingType) == lookupKey {
            count += 1
        }
    }
}

func reassignCalendarMeetingCategory(
    in records: [CalendarMeetingRecord],
    from sourceCategoryName: String,
    to replacementCategoryName: String?
) -> [CalendarMeetingRecord] {
    let sourceLookupKey = normalizedCalendarCategoryLookupKey(sourceCategoryName)
    guard !sourceLookupKey.isEmpty else { return records }

    let replacementName = replacementCategoryName?.trimmedOrNil ?? ""
    var didChange = false

    let updated = records.map { record in
        guard normalizedCalendarCategoryLookupKey(record.meetingType) == sourceLookupKey else {
            return record
        }
        var copy = record
        copy.meetingType = replacementName
        didChange = true
        return copy
    }

    return didChange ? updated : records
}

func normalizedCalendarCategoryHexColor(_ raw: String, fallback: String = "#000000") -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback }
    let cleaned = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    guard cleaned.count == 6, cleaned.allSatisfy(\.isHexDigit) else { return fallback }
    return "#\(cleaned.uppercased())"
}

/// The old fixed category names. The app now follows the category settings
/// "Clinical time" and "Leave" (Settings > Calendar categories); these names
/// only give those settings their defaults.
func isClinicCalendarCategoryName(_ raw: String) -> Bool {
    raw.caseInsensitiveCompare("Klinik") == .orderedSame
        || raw.caseInsensitiveCompare("Clinic") == .orderedSame
}

func isVacationCalendarCategoryName(_ raw: String) -> Bool {
    raw.caseInsensitiveCompare("Semester") == .orderedSame
        || raw.caseInsensitiveCompare("Vacation") == .orderedSame
}

struct CalendarMeetingRecord: Codable, Hashable, Identifiable {
    var id: String
    var date: String
    var startTime: String
    var endTime: String
    var title: String
    var meetingType: String
    var meetingMode: String
    var place: String
    var country: String
    var detail: String
    var participantNames: [String]
    /// Id links to the researchers in `participantNames`; the names stay as display text.
    var participantAuthorIDs: [String]
    var projectIDs: [String]
    var organizationIDs: [String]
    var applicationIDs: [String]
    var publicationIDs: [String]
    var mediaAppearanceIDs: [String]
    var projectID: String?
    var researcherID: String?
    var teachingAssignmentIDs: [String]
    var teachingAssignmentID: String?
    /// Teaching courses linked to this activity as a whole (the "Undervisning"
    /// row lets a course or one of its assignments be chosen). Optional in
    /// stored data: older activities decode with an empty list.
    var teachingCourseIDs: [String]
    /// Doctoral candidates explicitly linked to this activity. The singular
    /// companion preserves the same legacy-compatible shape as teaching links.
    var doctoralCandidateIDs: [String]
    var doctoralCandidateID: String?
    var organizationID: String?
    /// Meeting agenda; edited alongside the protocol in the calendar editors.
    var agendaText: String
    /// Meeting minutes; aggregated into the linked records' protocol documents.
    var protocolText: String

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case startTime
        case endTime
        case title
        case meetingType
        case meetingMode
        case place
        case country
        case detail
        case participantNames
        case participantAuthorIDs
        case projectIDs
        case organizationIDs
        case applicationIDs
        case publicationIDs
        case mediaAppearanceIDs
        case projectID
        case researcherID
        case teachingAssignmentIDs
        case teachingAssignmentID
        case teachingCourseIDs
        case doctoralCandidateIDs
        case doctoralCandidateID
        case organizationID
        case agendaText
        case protocolText
    }

    init(
        id: String = UUID().uuidString,
        date: String = "",
        startTime: String = "",
        endTime: String = "",
        title: String = "",
        meetingType: String = "",
        meetingMode: String = "",
        place: String = "",
        country: String = "",
        detail: String = "",
        participantNames: [String] = [],
        participantAuthorIDs: [String] = [],
        projectIDs: [String] = [],
        organizationIDs: [String] = [],
        applicationIDs: [String] = [],
        publicationIDs: [String] = [],
        mediaAppearanceIDs: [String] = [],
        projectID: String? = nil,
        researcherID: String? = nil,
        teachingAssignmentIDs: [String] = [],
        teachingAssignmentID: String? = nil,
        teachingCourseIDs: [String] = [],
        doctoralCandidateIDs: [String] = [],
        doctoralCandidateID: String? = nil,
        organizationID: String? = nil,
        agendaText: String = "",
        protocolText: String = ""
    ) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.meetingType = meetingType
        self.meetingMode = meetingMode
        self.place = place
        self.country = country
        self.detail = detail
        self.participantNames = participantNames
        self.participantAuthorIDs = participantAuthorIDs
        self.projectIDs = projectIDs
        self.organizationIDs = organizationIDs
        self.applicationIDs = applicationIDs
        self.publicationIDs = publicationIDs
        self.mediaAppearanceIDs = mediaAppearanceIDs
        self.projectID = projectID
        self.researcherID = researcherID
        self.teachingAssignmentIDs = teachingAssignmentIDs
        self.teachingAssignmentID = teachingAssignmentID
        self.teachingCourseIDs = teachingCourseIDs
        self.doctoralCandidateIDs = doctoralCandidateIDs
        self.doctoralCandidateID = doctoralCandidateID
        self.organizationID = organizationID
        self.agendaText = agendaText
        self.protocolText = protocolText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime) ?? ""
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        meetingType = try container.decodeIfPresent(String.self, forKey: .meetingType) ?? ""
        meetingMode = try container.decodeIfPresent(String.self, forKey: .meetingMode) ?? ""
        place = try container.decodeIfPresent(String.self, forKey: .place) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        participantNames = try container.decodeIfPresent([String].self, forKey: .participantNames) ?? []
        participantAuthorIDs = try container.decodeIfPresent([String].self, forKey: .participantAuthorIDs) ?? []
        projectIDs = try container.decodeIfPresent([String].self, forKey: .projectIDs) ?? []
        organizationIDs = try container.decodeIfPresent([String].self, forKey: .organizationIDs) ?? []
        applicationIDs = try container.decodeIfPresent([String].self, forKey: .applicationIDs) ?? []
        publicationIDs = try container.decodeIfPresent([String].self, forKey: .publicationIDs) ?? []
        mediaAppearanceIDs = try container.decodeIfPresent([String].self, forKey: .mediaAppearanceIDs) ?? []
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        researcherID = try container.decodeIfPresent(String.self, forKey: .researcherID)
        teachingAssignmentIDs = try container.decodeIfPresent([String].self, forKey: .teachingAssignmentIDs) ?? []
        teachingAssignmentID = try container.decodeIfPresent(String.self, forKey: .teachingAssignmentID)
        teachingCourseIDs = try container.decodeIfPresent([String].self, forKey: .teachingCourseIDs) ?? []
        doctoralCandidateIDs = try container.decodeIfPresent([String].self, forKey: .doctoralCandidateIDs) ?? []
        doctoralCandidateID = try container.decodeIfPresent(String.self, forKey: .doctoralCandidateID)
        organizationID = try container.decodeIfPresent(String.self, forKey: .organizationID)
        agendaText = try container.decodeIfPresent(String.self, forKey: .agendaText) ?? ""
        protocolText = try container.decodeIfPresent(String.self, forKey: .protocolText) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(title, forKey: .title)
        try container.encode(meetingType, forKey: .meetingType)
        try container.encode(meetingMode, forKey: .meetingMode)
        try container.encode(place, forKey: .place)
        try container.encode(country, forKey: .country)
        try container.encode(detail, forKey: .detail)
        try container.encode(participantNames, forKey: .participantNames)
        if !participantAuthorIDs.isEmpty {
            try container.encode(participantAuthorIDs, forKey: .participantAuthorIDs)
        }
        try container.encode(projectIDs, forKey: .projectIDs)
        try container.encode(organizationIDs, forKey: .organizationIDs)
        try container.encode(applicationIDs, forKey: .applicationIDs)
        try container.encode(publicationIDs, forKey: .publicationIDs)
        try container.encode(mediaAppearanceIDs, forKey: .mediaAppearanceIDs)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(researcherID, forKey: .researcherID)
        try container.encode(teachingAssignmentIDs, forKey: .teachingAssignmentIDs)
        try container.encodeIfPresent(teachingAssignmentID, forKey: .teachingAssignmentID)
        // Written only when set, so activities without a course link are
        // stored exactly as before.
        if !teachingCourseIDs.isEmpty {
            try container.encode(teachingCourseIDs, forKey: .teachingCourseIDs)
        }
        try container.encode(doctoralCandidateIDs, forKey: .doctoralCandidateIDs)
        try container.encodeIfPresent(doctoralCandidateID, forKey: .doctoralCandidateID)
        try container.encodeIfPresent(organizationID, forKey: .organizationID)
        try container.encode(agendaText, forKey: .agendaText)
        try container.encode(protocolText, forKey: .protocolText)
    }

    mutating func normalize() {
        date = DateParsers.canonicalizedDayInput(date)
        startTime = normalizedCalendarTimeInput(startTime)
        endTime = normalizedCalendarTimeInput(endTime)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingType = meetingType.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingMode = meetingMode.trimmingCharacters(in: .whitespacesAndNewlines)
        place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        country = GrantParsing.canonicalCountryName(country).trimmingCharacters(in: .whitespacesAndNewlines)
        if meetingMode.isEmpty {
            if place.caseInsensitiveCompare("Online") == .orderedSame {
                meetingMode = CalendarMeetingMode.online.rawValue
                place = ""
                country = ""
            } else if place.caseInsensitiveCompare("Fysiskt") == .orderedSame
                        || place.caseInsensitiveCompare("Physical") == .orderedSame {
                meetingMode = CalendarMeetingMode.physical.rawValue
                place = ""
                country = ""
            } else if place.caseInsensitiveCompare("Hybrid") == .orderedSame {
                meetingMode = CalendarMeetingMode.hybrid.rawValue
                place = ""
                country = ""
            }
        }
        if country.isEmpty, place.isEmpty == false {
            let split = splitLegacyCalendarMeetingPlace(place)
            place = split.place
            country = split.country
        }
        if meetingMode.caseInsensitiveCompare(CalendarMeetingMode.online.rawValue) == .orderedSame {
            place = ""
            country = ""
        }
        detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        participantNames = Array(
            NSOrderedSet(array: participantNames.compactMap(\.trimmedOrNil))
        ) as? [String] ?? participantNames.compactMap(\.trimmedOrNil)
        participantAuthorIDs = Array(
            NSOrderedSet(array: participantAuthorIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? participantAuthorIDs.compactMap(\.trimmedOrNil)
        projectIDs = Array(
            NSOrderedSet(array: projectIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? projectIDs.compactMap(\.trimmedOrNil)
        organizationIDs = Array(
            NSOrderedSet(array: organizationIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? organizationIDs.compactMap(\.trimmedOrNil)
        applicationIDs = Array(
            NSOrderedSet(array: applicationIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? applicationIDs.compactMap(\.trimmedOrNil)
        publicationIDs = Array(
            NSOrderedSet(array: publicationIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? publicationIDs.compactMap(\.trimmedOrNil)
        mediaAppearanceIDs = Array(
            NSOrderedSet(array: mediaAppearanceIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? mediaAppearanceIDs.compactMap(\.trimmedOrNil)
        projectID = projectID?.trimmedOrNil
        if projectIDs.isEmpty, let projectID {
            projectIDs = [projectID]
        }
        if let firstProjectID = projectIDs.first {
            projectID = firstProjectID
        } else {
            projectID = nil
        }
        researcherID = researcherID?.trimmedOrNil
        teachingAssignmentID = teachingAssignmentID?.trimmedOrNil
        teachingAssignmentIDs = Array(
            NSOrderedSet(array: teachingAssignmentIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? teachingAssignmentIDs.compactMap(\.trimmedOrNil)
        if teachingAssignmentIDs.isEmpty, let teachingAssignmentID {
            teachingAssignmentIDs = [teachingAssignmentID]
        }
        if let firstTeachingAssignmentID = teachingAssignmentIDs.first {
            teachingAssignmentID = firstTeachingAssignmentID
        } else {
            teachingAssignmentID = nil
        }
        teachingCourseIDs = Array(
            NSOrderedSet(array: teachingCourseIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? teachingCourseIDs.compactMap(\.trimmedOrNil)
        doctoralCandidateID = doctoralCandidateID?.trimmedOrNil
        doctoralCandidateIDs = Array(
            NSOrderedSet(array: doctoralCandidateIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? doctoralCandidateIDs.compactMap(\.trimmedOrNil)
        if doctoralCandidateIDs.isEmpty, let doctoralCandidateID {
            doctoralCandidateIDs = [doctoralCandidateID]
        }
        if let firstDoctoralCandidateID = doctoralCandidateIDs.first {
            doctoralCandidateID = firstDoctoralCandidateID
        } else {
            doctoralCandidateID = nil
        }
        organizationID = organizationID?.trimmedOrNil
        if organizationIDs.isEmpty, let organizationID {
            organizationIDs = [organizationID]
        }
        if let firstOrganizationID = organizationIDs.first {
            organizationID = firstOrganizationID
        } else {
            organizationID = nil
        }
        agendaText = agendaText.trimmingCharacters(in: .whitespacesAndNewlines)
        protocolText = protocolText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && startTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && meetingType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && meetingMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && participantNames.isEmpty
            && projectIDs.isEmpty
            && organizationIDs.isEmpty
            && applicationIDs.isEmpty
            && publicationIDs.isEmpty
            && mediaAppearanceIDs.isEmpty
            && projectID?.trimmedOrNil == nil
            && researcherID?.trimmedOrNil == nil
            && teachingAssignmentIDs.isEmpty
            && teachingAssignmentID?.trimmedOrNil == nil
            && teachingCourseIDs.isEmpty
            && doctoralCandidateIDs.isEmpty
            && doctoralCandidateID?.trimmedOrNil == nil
            && organizationID?.trimmedOrNil == nil
            && agendaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && protocolText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum CalendarTaskDisplayPolicy {
    case scheduled
    case rollOverPastDue
}

func normalizedCalendarTimeInput(_ raw: String?) -> String {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = trimmed.replacingOccurrences(of: ":", with: "")
    if digits.count == 4, digits.allSatisfy(\.isNumber) {
        let hours = Int(digits.prefix(2)) ?? -1
        let minutes = Int(digits.suffix(2)) ?? -1
        if (0..<24).contains(hours), (0..<60).contains(minutes) {
            return "\(String(format: "%02d", hours)):\(String(format: "%02d", minutes))"
        }
    }
    if digits.count == 3, digits.allSatisfy(\.isNumber) {
        let chars = Array(digits)
        let hours = Int(String(chars[0])) ?? -1
        let minutes = Int(String(chars[1...2])) ?? -1
        if (0..<24).contains(hours), (0..<60).contains(minutes) {
            return "\(String(format: "%02d", hours)):\(String(format: "%02d", minutes))"
        }
    }
    return trimmed
}
