import Foundation

enum HolidayCountry: String, CaseIterable, Codable, Hashable, Identifiable {
    case sweden
    case norway

    var id: String { rawValue }

    func localizedName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.sweden, .swedish):
            return "Sverige"
        case (.sweden, .english):
            return "Sweden"
        case (.norway, .swedish):
            return "Norge"
        case (.norway, .english):
            return "Norway"
        }
    }
}

struct HolidayDefinition: Identifiable, Hashable {
    let country: HolidayCountry
    let key: String
    let date: Date
    let titleSv: String
    let titleEn: String

    var id: String {
        "\(country.rawValue)|\(key)|\(DateParsers.isoDay.string(from: date))"
    }

    func localizedTitle(language: AppLanguage) -> String {
        language == .swedish ? titleSv : titleEn
    }
}

enum HolidayCalendarBuilder {
    static func holidays(in monthStart: Date, countries: [HolidayCountry], calendar: Calendar) -> [HolidayDefinition] {
        let normalizedCountries = normalized(countries)
        guard !normalizedCountries.isEmpty else { return [] }
        let year = calendar.component(.year, from: monthStart)
        let month = calendar.component(.month, from: monthStart)
        return holidays(for: normalizedCountries, year: year, calendar: calendar)
            .filter {
                calendar.component(.year, from: $0.date) == year &&
                calendar.component(.month, from: $0.date) == month
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date < rhs.date
                }
                if lhs.country != rhs.country {
                    return lhs.country.rawValue < rhs.country.rawValue
                }
                return lhs.localizedTitle(language: .swedish).localizedStandardCompare(rhs.localizedTitle(language: .swedish)) == .orderedAscending
            }
    }

    static func holidays(for countries: [HolidayCountry], year: Int, calendar: Calendar) -> [HolidayDefinition] {
        normalized(countries).flatMap { country in
            switch country {
            case .sweden:
                return swedishHolidays(year: year, calendar: calendar)
            case .norway:
                return norwegianHolidays(year: year, calendar: calendar)
            }
        }
    }

    static func easterSunday(year: Int, calendar: Calendar) -> Date? {
        // Gregorian computus based on the ecclesiastical Easter tables.
        let century = year / 100
        let goldenNumber = year - 19 * (year / 19)
        let correction = (century - 17) / 25
        var epact = century - century / 4 - (century - correction) / 3 + 19 * goldenNumber + 15
        epact = epact - 30 * (epact / 30)
        epact = epact - (epact / 28) * (1 - (epact / 28) * (29 / (epact + 1)) * ((21 - goldenNumber) / 11))
        var weekday = year + year / 4 + epact + 2 - century + century / 4
        weekday = weekday - 7 * (weekday / 7)
        let offset = epact - weekday
        let month = 3 + (offset + 40) / 44
        let day = offset + 28 - 31 * (month / 4)
        return fixedDate(year: year, month: month, day: day, calendar: calendar)
    }

    static func normalized(_ countries: [HolidayCountry]) -> [HolidayCountry] {
        HolidayCountry.allCases.filter(countries.contains)
    }

    private static func swedishHolidays(year: Int, calendar: Calendar) -> [HolidayDefinition] {
        var holidays = [
            holiday(.sweden, "newYearsDay", year, 1, 1, "Nyårsdagen", "New Year's Day", calendar),
            holiday(.sweden, "twelfthNight", year, 1, 5, "Trettondagsafton", "Twelfth Night", calendar),
            holiday(.sweden, "epiphany", year, 1, 6, "Trettondedag jul", "Epiphany", calendar),
            holiday(.sweden, "walpurgisEve", year, 4, 30, "Valborgsmässoafton", "Walpurgis Eve", calendar),
            holiday(.sweden, "mayDay", year, 5, 1, "Första maj", "May Day", calendar),
            holiday(.sweden, "nationalDay", year, 6, 6, "Sveriges nationaldag", "National Day of Sweden", calendar),
            holiday(.sweden, "christmasEve", year, 12, 24, "Julafton", "Christmas Eve", calendar),
            holiday(.sweden, "christmasDay", year, 12, 25, "Juldagen", "Christmas Day", calendar),
            holiday(.sweden, "boxingDay", year, 12, 26, "Annandag jul", "Boxing Day", calendar),
            holiday(.sweden, "newYearsEve", year, 12, 31, "Nyårsafton", "New Year's Eve", calendar)
        ].compactMap { $0 }

        if let easterSunday = easterSunday(year: year, calendar: calendar) {
            holidays.append(contentsOf: [
                relativeHoliday(.sweden, "maundyThursday", easterSunday, -3, "Skärtorsdagen", "Maundy Thursday", calendar),
                relativeHoliday(.sweden, "goodFriday", easterSunday, -2, "Långfredagen", "Good Friday", calendar),
                relativeHoliday(.sweden, "easterEve", easterSunday, -1, "Påskafton", "Easter Eve", calendar),
                relativeHoliday(.sweden, "easterSunday", easterSunday, 0, "Påskdagen", "Easter Sunday", calendar),
                relativeHoliday(.sweden, "easterMonday", easterSunday, 1, "Annandag påsk", "Easter Monday", calendar),
                relativeHoliday(.sweden, "ascensionDay", easterSunday, 39, "Kristi himmelsfärdsdag", "Ascension Day", calendar),
                relativeHoliday(.sweden, "pentecostEve", easterSunday, 48, "Pingstafton", "Pentecost Eve", calendar),
                relativeHoliday(.sweden, "pentecostSunday", easterSunday, 49, "Pingstdagen", "Pentecost Sunday", calendar)
            ].compactMap { $0 })
        }

        if let midsummerEve = firstWeekday(
            weekday: 6,
            year: year,
            startMonth: 6,
            startDay: 19,
            endMonth: 6,
            endDay: 25,
            calendar: calendar
        ) {
            holidays.append(
                HolidayDefinition(
                    country: .sweden,
                    key: "midsummerEve",
                    date: midsummerEve,
                    titleSv: "Midsommarafton",
                    titleEn: "Midsummer Eve"
                )
            )
        }

        if let midsummerDay = firstWeekday(
            weekday: 7,
            year: year,
            startMonth: 6,
            startDay: 20,
            endMonth: 6,
            endDay: 26,
            calendar: calendar
        ) {
            holidays.append(
                HolidayDefinition(
                    country: .sweden,
                    key: "midsummerDay",
                    date: midsummerDay,
                    titleSv: "Midsommardagen",
                    titleEn: "Midsummer Day"
                )
            )
        }

        if let allSaintsEve = firstWeekday(
            weekday: 6,
            year: year,
            startMonth: 10,
            startDay: 30,
            endMonth: 11,
            endDay: 5,
            calendar: calendar
        ) {
            holidays.append(
                HolidayDefinition(
                    country: .sweden,
                    key: "allSaintsEve",
                    date: allSaintsEve,
                    titleSv: "Allhelgonaafton",
                    titleEn: "All Saints' Eve"
                )
            )
        }

        if let allSaintsDay = firstWeekday(
            weekday: 7,
            year: year,
            startMonth: 10,
            startDay: 31,
            endMonth: 11,
            endDay: 6,
            calendar: calendar
        ) {
            holidays.append(
                HolidayDefinition(
                    country: .sweden,
                    key: "allSaintsDay",
                    date: allSaintsDay,
                    titleSv: "Alla helgons dag",
                    titleEn: "All Saints' Day"
                )
            )
        }

        return holidays
    }

    private static func norwegianHolidays(year: Int, calendar: Calendar) -> [HolidayDefinition] {
        var holidays = [
            holiday(.norway, "newYearsDay", year, 1, 1, "Første nyttårsdag", "New Year's Day", calendar),
            holiday(.norway, "labourDay", year, 5, 1, "Arbeidernes dag", "Labour Day", calendar),
            holiday(.norway, "constitutionDay", year, 5, 17, "Grunnlovsdagen", "Constitution Day", calendar),
            holiday(.norway, "christmasDay", year, 12, 25, "Første juledag", "Christmas Day", calendar),
            holiday(.norway, "boxingDay", year, 12, 26, "Andre juledag", "Boxing Day", calendar)
        ].compactMap { $0 }

        if let easterSunday = easterSunday(year: year, calendar: calendar) {
            holidays.append(contentsOf: [
                relativeHoliday(.norway, "maundyThursday", easterSunday, -3, "Skjærtorsdag", "Maundy Thursday", calendar),
                relativeHoliday(.norway, "goodFriday", easterSunday, -2, "Langfredag", "Good Friday", calendar),
                relativeHoliday(.norway, "easterSunday", easterSunday, 0, "Første påskedag", "Easter Sunday", calendar),
                relativeHoliday(.norway, "easterMonday", easterSunday, 1, "Andre påskedag", "Easter Monday", calendar),
                relativeHoliday(.norway, "ascensionDay", easterSunday, 39, "Kristi himmelsfartsdag", "Ascension Day", calendar),
                relativeHoliday(.norway, "pentecostSunday", easterSunday, 49, "Første pinsedag", "Pentecost Sunday", calendar),
                relativeHoliday(.norway, "pentecostMonday", easterSunday, 50, "Andre pinsedag", "Pentecost Monday", calendar)
            ].compactMap { $0 })
        }

        return holidays
    }

    private static func holiday(
        _ country: HolidayCountry,
        _ key: String,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ titleSv: String,
        _ titleEn: String,
        _ calendar: Calendar
    ) -> HolidayDefinition? {
        guard let date = fixedDate(year: year, month: month, day: day, calendar: calendar) else { return nil }
        return HolidayDefinition(country: country, key: key, date: date, titleSv: titleSv, titleEn: titleEn)
    }

    private static func relativeHoliday(
        _ country: HolidayCountry,
        _ key: String,
        _ baseDate: Date,
        _ dayOffset: Int,
        _ titleSv: String,
        _ titleEn: String,
        _ calendar: Calendar
    ) -> HolidayDefinition? {
        guard let date = calendar.date(byAdding: .day, value: dayOffset, to: baseDate) else { return nil }
        return HolidayDefinition(
            country: country,
            key: key,
            date: calendar.startOfDay(for: date),
            titleSv: titleSv,
            titleEn: titleEn
        )
    }

    private static func fixedDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day)).map(calendar.startOfDay(for:))
    }

    private static func firstWeekday(
        weekday: Int,
        year: Int,
        startMonth: Int,
        startDay: Int,
        endMonth: Int,
        endDay: Int,
        calendar: Calendar
    ) -> Date? {
        guard let startDate = fixedDate(year: year, month: startMonth, day: startDay, calendar: calendar),
              let endDate = fixedDate(year: year, month: endMonth, day: endDay, calendar: calendar) else {
            return nil
        }

        var current = startDate
        while current <= endDate {
            if calendar.component(.weekday, from: current) == weekday {
                return current
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = next
        }
        return nil
    }
}
