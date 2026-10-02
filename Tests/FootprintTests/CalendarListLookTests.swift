import XCTest
@testable import Footprint

/// Calendar list look: week header row, merged day column and meeting icons.
/// Only pure helpers are tested here; all values below are made up.
final class CalendarListLookTests: XCTestCase {

    // MARK: Week header row

    func testWeekHeaderAcrossTwoMonths() {
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: 40,
                startDay: 28, startMonth: 9, startYear: 2026,
                endDay: 4, endMonth: 10, endYear: 2026,
                showsYear: true,
                language: .swedish
            ),
            "Vecka 40 · 28 sep – 4 okt 2026"
        )
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: 40,
                startDay: 28, startMonth: 9, startYear: 2026,
                endDay: 4, endMonth: 10, endYear: 2026,
                showsYear: true,
                language: .english
            ),
            "Week 40 · 28 Sep – 4 Oct 2026"
        )
    }

    func testWeekHeaderInsideOneMonthNamesTheMonthOnce() {
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: 41,
                startDay: 5, startMonth: 10, startYear: 2026,
                endDay: 11, endMonth: 10, endYear: 2026,
                showsYear: true,
                language: .swedish
            ),
            "Vecka 41 · 5 – 11 okt 2026"
        )
    }

    func testWeekHeaderLeavesOutHiddenWeekNumberAndYear() {
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: nil,
                startDay: 28, startMonth: 9, startYear: 2026,
                endDay: 4, endMonth: 10, endYear: 2026,
                showsYear: true,
                language: .swedish
            ),
            "28 sep – 4 okt 2026"
        )
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: 40,
                startDay: 28, startMonth: 9, startYear: 2026,
                endDay: 4, endMonth: 10, endYear: 2026,
                showsYear: false,
                language: .swedish
            ),
            "Vecka 40 · 28 sep – 4 okt"
        )
    }

    func testWeekHeaderAcrossNewYearShowsBothYears() {
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: 53,
                startDay: 28, startMonth: 12, startYear: 2026,
                endDay: 3, endMonth: 1, endYear: 2027,
                showsYear: true,
                language: .swedish
            ),
            "Vecka 53 · 28 dec 2026 – 3 jan 2027"
        )
    }

    // MARK: Merged day column

    func testShortDayLabel() {
        // Calendar weekday 6 is Friday.
        XCTAssertEqual(calendarListShortDayLabel(weekday: 6, day: 2, month: 10, language: .swedish), "Fre 2 okt")
        XCTAssertEqual(calendarListShortDayLabel(weekday: 6, day: 2, month: 10, language: .english), "Fri 2 Oct")
        XCTAssertEqual(calendarListShortDayLabel(weekday: 1, day: 3, month: 5, language: .swedish), "Sön 3 maj")
    }

    // MARK: Meeting icons

    func testOnlineAndInPersonMeetingsGetDifferentIcons() {
        XCTAssertEqual(calendarMeetingCategoryIconName(place: "Online"), "video")
        XCTAssertEqual(calendarMeetingCategoryIconName(place: " online "), "video")
        XCTAssertEqual(calendarMeetingCategoryIconName(place: "Telefon"), "phone")
        XCTAssertEqual(calendarMeetingCategoryIconName(place: "Exempelstad"), "person.2")
        XCTAssertEqual(calendarMeetingCategoryIconName(place: ""), "person.2")
    }

    // MARK: Title with organisation

    func testTitleGetsOrganisationInParentheses() {
        XCTAssertEqual(
            calendarListTitleText(title: "Intervju postdoc", organization: "Påhittat universitet"),
            "Intervju postdoc (Påhittat universitet)"
        )
        XCTAssertEqual(
            calendarListTitleText(title: "Intervju postdoc", organization: "  Påhittat universitet "),
            "Intervju postdoc (Påhittat universitet)"
        )
    }

    func testTitleWithoutOrHiddenOrganisationStaysAsItIs() {
        XCTAssertEqual(calendarListTitleText(title: "Intervju postdoc", organization: nil), "Intervju postdoc")
        XCTAssertEqual(calendarListTitleText(title: "Intervju postdoc", organization: " "), "Intervju postdoc")
    }

    func testOrganisationIsNotRepeatedOrShownWithoutTitle() {
        // A grant whose title falls back to the funder's name.
        XCTAssertEqual(calendarListTitleText(title: "Exempelfonden", organization: "exempelfonden"), "Exempelfonden")
        XCTAssertEqual(
            calendarListTitleText(title: "Möte (Exempelfonden)", organization: "Exempelfonden"),
            "Möte (Exempelfonden)"
        )
        // Leave categories show no title, so nothing to put it after.
        XCTAssertEqual(calendarListTitleText(title: "", organization: "Exempelfonden"), "")
    }

    // MARK: Participants apart from the title

    func testMeetingTitleKeepsParticipantsApartForTheList() {
        let parts = calendarMeetingTitleParts(
            title: "Möte",
            participantNames: ["Anna Exempel", "Bertil Exempel"],
            isLeave: false,
            language: .swedish
        )
        // The rest of the app keeps the old title with participants.
        XCTAssertEqual(parts.title, "Möte (Anna Exempel, Bertil Exempel)")
        XCTAssertEqual(parts.listTitle, "Möte")
        XCTAssertEqual(parts.participantNames, ["Anna Exempel", "Bertil Exempel"])
    }

    func testMeetingTitleWithoutParticipantsOrTitle() {
        let parts = calendarMeetingTitleParts(title: " ", participantNames: [], isLeave: false, language: .swedish)
        XCTAssertEqual(parts.title, "Aktivitet")
        XCTAssertEqual(parts.listTitle, "Aktivitet")
        XCTAssertEqual(parts.participantNames, [])
    }

    func testLeaveMeetingShowsNoTitleAndNoParticipants() {
        let parts = calendarMeetingTitleParts(
            title: "Semester",
            participantNames: ["Anna Exempel"],
            isLeave: true,
            language: .swedish
        )
        XCTAssertEqual(parts, CalendarMeetingTitleParts(title: "", listTitle: "", participantNames: []))
    }

    func testParticipantsLineSkipsBlanksAndRepeats() {
        XCTAssertEqual(
            calendarListParticipantsText(["Anna Exempel", " ", "Bertil Exempel ", "Anna Exempel"]),
            "Anna Exempel, Bertil Exempel"
        )
        XCTAssertEqual(calendarListParticipantsText([]), "")
    }

    // MARK: Detail parts and "Visa i raden"

    func testDetailPartsKeepOnlyPartsWithText() {
        let parts = calendarDetailParts([
            (nil, "Hybrid"),
            (.note, " "),
            (.publication, "Publikation: Påhittad studie"),
            (.application, nil)
        ])
        XCTAssertEqual(parts, [
            CalendarWorkspaceDetailPart(nil, "Hybrid"),
            CalendarWorkspaceDetailPart(.publication, "Publikation: Påhittad studie")
        ])
    }

    func testHiddenDetailPartsAreLeftOutOfTheRow() {
        let event = makeEvent(
            detail: "Hybrid · Agenda · Publikation: Påhittad studie · Anslag: Påhittat anslag",
            detailParts: [
                CalendarWorkspaceDetailPart(nil, "Hybrid"),
                CalendarWorkspaceDetailPart(.note, "Agenda"),
                CalendarWorkspaceDetailPart(.publication, "Publikation: Påhittad studie"),
                CalendarWorkspaceDetailPart(.application, "Anslag: Påhittat anslag")
            ]
        )
        XCTAssertEqual(
            calendarListVisibleDetailText(for: event, hiddenKinds: [], language: .swedish),
            "Hybrid · Agenda · Publikation: Påhittad studie · Anslag: Påhittat anslag"
        )
        XCTAssertEqual(
            calendarListVisibleDetailText(for: event, hiddenKinds: [.publication, .application], language: .swedish),
            "Hybrid · Agenda"
        )
        // Parts without a kind always show.
        XCTAssertEqual(
            calendarListVisibleDetailText(
                for: event,
                hiddenKinds: Set(CalendarListDetailKind.allCases),
                language: .swedish
            ),
            "Hybrid"
        )
    }

    func testRowsWithoutPartsShowTheirWholeDetail() {
        let event = makeEvent(detail: "Accepterat: 2026-09-01", detailParts: nil, isDateUncertain: true)
        XCTAssertEqual(
            calendarListVisibleDetailText(for: event, hiddenKinds: Set(CalendarListDetailKind.allCases), language: .swedish),
            "Osäkert datum · Accepterat: 2026-09-01"
        )
    }

    func testDetailSettingsHaveSwedishNamesAndDistinctStorageKeys() {
        XCTAssertEqual(CalendarListDetailKind.participants.title(language: .swedish), "Deltagare")
        XCTAssertEqual(CalendarListDetailKind.organization.title(language: .swedish), "Organisation")
        XCTAssertEqual(CalendarListDetailKind.publication.title(language: .swedish), "Publikation")
        XCTAssertEqual(CalendarListDetailKind.application.title(language: .swedish), "Ansökan")
        XCTAssertEqual(CalendarListDetailKind.teaching.title(language: .swedish), "Undervisning")
        let keys = CalendarListDetailKind.allCases.map(\.hiddenStorageKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("rowDetail.") })
    }

    // MARK: Link symbols

    func testLinkSymbolFollowsWhatTheLinkOpens() {
        XCTAssertEqual(calendarListLinkSymbolName(for: .project), AppTab.projects.symbolName)
        XCTAssertEqual(calendarListLinkSymbolName(for: .publication), AppTab.publications.symbolName)
        XCTAssertEqual(calendarListLinkSymbolName(for: .application), AppTab.applications.symbolName)
        XCTAssertEqual(calendarListLinkSymbolName(for: .organization), AppTab.organizations.symbolName)
        XCTAssertEqual(calendarListLinkSymbolName(for: .congress), AppTab.congresses.symbolName)
        XCTAssertEqual(calendarListLinkSymbolName(for: .doctoralCandidate), AppTab.doctoralCandidates.symbolName)
        XCTAssertEqual(calendarListLinkSymbolName(for: .teaching), AppTab.teaching.symbolName)
        XCTAssertEqual(calendarListLinkSymbolName(for: .web), "link")
    }

    private func makeEvent(
        detail: String,
        detailParts: [CalendarWorkspaceDetailPart]?,
        isDateUncertain: Bool = false
    ) -> CalendarWorkspaceEvent {
        CalendarWorkspaceEvent(
            id: "meeting:example",
            source: .meeting("example"),
            displayDate: Date(timeIntervalSince1970: 0),
            isDateUncertain: isDateUncertain,
            title: "Möte",
            subtitle: "",
            detail: detail,
            place: "",
            timeText: "",
            kind: .meeting,
            detailParts: detailParts,
            completedOn: nil,
            action: nil,
            toggleCompletion: nil
        )
    }
}
