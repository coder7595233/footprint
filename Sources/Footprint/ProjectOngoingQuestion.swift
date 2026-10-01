import Foundation
import SwiftUI

/// Round 16 (user decision 2026-10-01): when a PLANNED project gets granted
/// funds, a data collection with a start date, or an ethics application or
/// approval date, the app asks "Ska projektet ändras till Pågående?".
/// "Inte nu" remembers that exact event on the project, so the same event is
/// not asked about again, while a new event asks again. Ongoing and
/// completed projects are never asked.
enum ProjectOngoingPrompt {
    static func grantedKey(applicationID: String) -> String {
        "granted:\(applicationID)"
    }

    static func dataCollectionKey(id: String) -> String {
        "dataCollection:\(id)"
    }

    static func ethicsAppliedKey(id: String) -> String {
        "ethicsApplied:\(id)"
    }

    static func ethicsApprovedKey(id: String) -> String {
        "ethicsApproved:\(id)"
    }

    /// The events that are new in `current` compared with `previous`: a data
    /// collection that got a start date, and an ethics application (base or
    /// amendment) that got an application or approval date.
    static func newTriggerKeys(previous: ProjectRecord?, current: ProjectRecord) -> [String] {
        var keys: [String] = []

        let previousStarts = Dictionary(
            (previous?.dataCollections ?? []).map { ($0.id, $0.from.trimmedOrNil) },
            uniquingKeysWith: { first, _ in first }
        )
        for collection in current.dataCollections where collection.from.trimmedOrNil != nil {
            if (previousStarts[collection.id] ?? nil) == nil {
                keys.append(dataCollectionKey(id: collection.id))
            }
        }

        let previousEthics = previous.map { [$0.ethicsBaseApplication] + $0.ethicsAmendments } ?? []
        let previousByID = Dictionary(previousEthics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for ethics in [current.ethicsBaseApplication] + current.ethicsAmendments {
            let before = previousByID[ethics.id]
            if ethics.appliedOn.trimmedOrNil != nil, before?.appliedOn.trimmedOrNil == nil {
                keys.append(ethicsAppliedKey(id: ethics.id))
            }
            if ethics.grantedOn.trimmedOrNil != nil, before?.grantedOn.trimmedOrNil == nil {
                keys.append(ethicsApprovedKey(id: ethics.id))
            }
        }
        return keys
    }

    /// True when the application became granted for this project now (it
    /// was not already granted and linked to the same project before).
    static func becameGrantedForProject(
        previous: GrantApplication?,
        previousProjectID: String?,
        current: GrantApplication,
        currentProjectID: String?
    ) -> Bool {
        guard current.isGranted, let currentProjectID else { return false }
        guard let previous else { return true }
        return !(previous.isGranted && previousProjectID == currentProjectID)
    }

    /// The keys still to ask about: only for planned, unlocked projects, and
    /// never for an event already answered "Inte nu".
    static func keysToAsk(project: ProjectRecord, keys: [String]) -> [String] {
        guard project.projectStatus == .planned, !project.isEditingLocked else { return [] }
        let dismissed = Set(project.dismissedOngoingPromptKeys ?? [])
        var seen = Set<String>()
        return keys.filter { !dismissed.contains($0) && seen.insert($0).inserted }
    }

    static func addingDismissed(_ keys: [String], to existing: [String]?) -> [String]? {
        let merged = (existing ?? []) + keys.filter { !(existing ?? []).contains($0) }
        return merged.isEmpty ? nil : merged
    }

    /// Answers are kept when an editor saves an older copy of the project.
    static func mergedDismissedKeys(_ previous: ProjectRecord, _ draft: ProjectRecord) -> [String]? {
        addingDismissed(draft.dismissedOngoingPromptKeys ?? [], to: previous.dismissedOngoingPromptKeys)
    }
}

/// The open question: which project, and which events it is about.
struct ProjectOngoingQuestion: Equatable {
    let projectID: String
    var triggerKeys: [String]
}

extension GrantDataStore {
    /// Called after a project is saved.
    func evaluateOngoingQuestion(previous: ProjectRecord?, current: ProjectRecord) {
        presentOngoingQuestionIfNeeded(
            project: current,
            keys: ProjectOngoingPrompt.newTriggerKeys(previous: previous, current: current)
        )
    }

    /// Called after an application is saved: asks when it became granted
    /// and is linked to a planned project.
    func evaluateOngoingQuestion(previousApplication: GrantApplication?, application: GrantApplication) {
        guard let project = linkedProject(of: application) else { return }
        let previousProjectID = previousApplication.flatMap { linkedProject(of: $0)?.id }
        guard ProjectOngoingPrompt.becameGrantedForProject(
            previous: previousApplication,
            previousProjectID: previousProjectID,
            current: application,
            currentProjectID: project.id
        ) else { return }
        presentOngoingQuestionIfNeeded(
            project: project,
            keys: [ProjectOngoingPrompt.grantedKey(applicationID: application.id)]
        )
    }

    private func presentOngoingQuestionIfNeeded(project: ProjectRecord, keys: [String]) {
        let toAsk = ProjectOngoingPrompt.keysToAsk(project: project, keys: keys)
        guard !toAsk.isEmpty else { return }
        if var open = pendingOngoingQuestion, open.projectID == project.id {
            open.triggerKeys += toAsk.filter { !open.triggerKeys.contains($0) }
            pendingOngoingQuestion = open
        } else {
            pendingOngoingQuestion = ProjectOngoingQuestion(projectID: project.id, triggerKeys: toAsk)
        }
    }

    /// "Ja" sets the project to ongoing; "Inte nu" remembers the events.
    /// Both are saved like any other project change, so they can be undone.
    func answerOngoingQuestion(_ question: ProjectOngoingQuestion, setOngoing: Bool) {
        if pendingOngoingQuestion == question {
            pendingOngoingQuestion = nil
        }
        guard var record = project(id: question.projectID), record.projectStatus == .planned else { return }
        if setOngoing {
            record.projectStatus = .ongoing
        } else {
            record.dismissedOngoingPromptKeys = ProjectOngoingPrompt.addingDismissed(
                question.triggerKeys,
                to: record.dismissedOngoingPromptKeys
            )
        }
        updateProjectRecord(record, previousID: record.id)
    }
}

/// The question "Ska projektet ändras till Pågående?" shown over the whole app.
struct ProjectOngoingQuestionAlertModifier: ViewModifier {
    @ObservedObject var store: GrantDataStore
    let language: AppLanguage

    private var project: ProjectRecord? {
        guard let id = store.pendingOngoingQuestion?.projectID else { return nil }
        return store.project(id: id)
    }

    func body(content: Content) -> some View {
        content.alert(
            language.text("Change the project to Ongoing?", "Ska projektet ändras till Pågående?"),
            isPresented: Binding(
                get: { store.pendingOngoingQuestion != nil },
                set: { isPresented in
                    if !isPresented {
                        store.pendingOngoingQuestion = nil
                    }
                }
            ),
            actions: {
                // The question is captured here, so the answer works whether
                // the alert closes before or after the button's action.
                if let question = store.pendingOngoingQuestion {
                    Button(language.text("Yes", "Ja")) {
                        store.answerOngoingQuestion(question, setOngoing: true)
                    }
                    Button(language.text("Not now", "Inte nu"), role: .cancel) {
                        store.answerOngoingQuestion(question, setOngoing: false)
                    }
                }
            },
            message: {
                if let project {
                    Text(language.text(
                        "\(project.displayName(for: language)) is planned but now has granted funds, a data collection or an ethics application.",
                        "\(project.displayName(for: language)) är planerat men har nu beviljade medel, en datainsamling eller en etikansökan."
                    ))
                }
            }
        )
    }
}
