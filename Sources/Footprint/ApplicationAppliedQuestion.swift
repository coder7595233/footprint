import Foundation
import SwiftUI

extension GrantApplication {
    /// "Att söka" whose closing date has passed without "Sökt" or "Ej sökt"
    /// being filled in. Such a call stays in the lists and is asked about
    /// in the calendar every day until it is answered.
    func awaitsAppliedAnswer(today: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isToApplyStatus,
              !isEditingLocked,
              appliedOn?.trimmedOrNil == nil,
              notAppliedOn?.trimmedOrNil == nil,
              let closeDate = closeDate
        else { return false }
        return calendar.startOfDay(for: closeDate) < calendar.startOfDay(for: today)
    }
}

extension GrantDataStore {
    /// Calls whose closing date has passed and that still need the answer
    /// "Sökt" or "Ej sökt", oldest closing date first.
    func applicationsAwaitingAppliedAnswer(today: Date = Date()) -> [GrantApplication] {
        applicationsForRead
            .filter { $0.awaitsAppliedAnswer(today: today) }
            .sorted { ($0.closeDate ?? .distantPast) < ($1.closeDate ?? .distantPast) }
    }

    func askAppliedQuestion(applicationID: String) {
        pendingAppliedQuestionApplicationID = applicationID
    }

    /// Answers the question for one call. "Sökt" sets the applied date to
    /// the closing date, marked as uncertain so it can be corrected;
    /// "Ej sökt" sets the not-applied date to the closing date. Saved like
    /// any other change, so it can be undone.
    @discardableResult
    func answerAppliedQuestion(applicationID: String, applied: Bool, today: Date = Date()) -> Bool {
        pendingAppliedQuestionApplicationID = nil
        guard var application = applications.first(where: { $0.id == applicationID }),
              application.awaitsAppliedAnswer(today: today),
              let closeDate = application.closeDate
        else { return false }
        let closingDay = DateParsers.isoDay.string(from: closeDate)
        if applied {
            application.appliedOn = closingDay
            application.appliedOnUncertain = true
            application.notAppliedOn = nil
            application.notAppliedOnUncertain = false
            application.result = nil
        } else {
            application.notAppliedOn = closingDay
            application.notAppliedOnUncertain = false
            application.appliedOn = nil
            application.appliedOnUncertain = false
            application.result = "Ej sökt"
        }
        save(application: application)
        return applications.first(where: { $0.id == applicationID })?.awaitsAppliedAnswer(today: today) == false
    }
}

/// The question "Sökt eller inte sökt?" shown over the whole app.
struct AppliedQuestionAlertModifier: ViewModifier {
    @ObservedObject var store: GrantDataStore
    let language: AppLanguage

    private var application: GrantApplication? {
        guard let id = store.pendingAppliedQuestionApplicationID else { return nil }
        return store.applicationsForRead.first { $0.id == id }
    }

    func body(content: Content) -> some View {
        content.alert(
            language.text("Did you apply?", "Sökt eller inte sökt?"),
            isPresented: Binding(
                get: { store.pendingAppliedQuestionApplicationID != nil },
                set: { isPresented in
                    if !isPresented {
                        store.pendingAppliedQuestionApplicationID = nil
                    }
                }
            ),
            actions: {
                if let application {
                    Button(language.text("Applied", "Sökt")) {
                        store.answerAppliedQuestion(applicationID: application.id, applied: true)
                    }
                    Button(language.text("Did not apply", "Ej sökt")) {
                        store.answerAppliedQuestion(applicationID: application.id, applied: false)
                    }
                    Button(language.text("Open application", "Öppna ansökan")) {
                        store.pendingAppliedQuestionApplicationID = nil
                        store.openRoute(for: application)
                    }
                }
                Button(language.text("Later", "Senare"), role: .cancel) {
                    store.pendingAppliedQuestionApplicationID = nil
                }
            },
            message: {
                if let application {
                    let title = store.localizedGrantName(for: application, language: language).nonEmpty
                        ?? store.organizationLabel(for: application, language: language)
                    let closing = application.closesOn?.trimmedOrNil ?? ""
                    Text(language.text(
                        "\(title) closed \(closing). Did you apply? \"Applied\" sets the applied date to the closing date (marked uncertain, so you can change it).",
                        "\(title) stängde \(closing). Sökte du? \"Sökt\" sätter ansökningsdatum till stängningsdagen (markerat som osäkert, så du kan ändra det)."
                    ))
                }
            }
        )
    }
}
