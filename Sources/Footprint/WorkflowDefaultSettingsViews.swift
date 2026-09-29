import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings cards for `WorkflowDefaultSettings`. One view type is used for the
/// three places in Settings (Applications, Teaching terms and Export); `part`
/// chooses which cards are shown. Every field starts with today's value, and
/// clearing a text field returns it to the built-in text.
struct WorkflowDefaultSettingsPanel: View {
    enum Part {
        case applications
        case teaching
        case export
    }

    @ObservedObject var store: GrantDataStore
    let part: Part

    @State private var draft = WorkflowDefaultSettings()
    @State private var currencyListText = ""
    @State private var clinicalWordsText = ""
    @State private var teachingMeritsTemplatePath = ""
    @State private var hasLoaded = false
    @State private var saveTask: Task<Void, Never>?

    private var language: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch part {
            case .applications:
                newApplicationCard
                currencyCard
                amountBucketCard
            case .teaching:
                teachingCard
            case .export:
                teachingMeritsCard
                statementTemplatesCard
            }
        }
        .onAppear(perform: load)
        .onChange(of: draft) { _, newValue in
            scheduleSave(newValue)
        }
        .onDisappear {
            saveTask?.cancel()
            if hasLoaded {
                store.autosaveWorkflowDefaultSettings(draft)
            }
        }
    }

    // MARK: Applications

    private var newApplicationCard: some View {
        card {
            header(
                language.text("New applications", "Nya ansökningar"),
                resetTitle: language.text("Reset", "Återställ")
            ) {
                draft.newApplicationOpensAfterMonths = nil
                draft.newApplicationClosesAfterMonths = nil
                draft.newApplicationCurrency = nil
                draft.newApplicationStatus = nil
            }

            explanation(language.text(
                "Values filled in when you add a new application. The dates are counted from the day you add it.",
                "Värden som fylls i när du lägger till en ny ansökan. Datumen räknas från dagen då du lägger till den."
            ))

            labeledRow(language.text("Call opens after (months)", "Utlysningen öppnar efter (månader)")) {
                TextField("", value: intBinding(\.newApplicationOpensAfterMonths, default: WorkflowDefaultSettings.defaultOpensAfterMonths), format: .number)
                    .frame(width: 120)
                    .appTextInputChrome(fillsWidth: false)
            }
            effect(language.text(
                "Affects: the \"Call opens\" date filled in on a new application (today plus this many months). Existing applications are not changed.",
                "Påverkar: datumet Utlysningen öppnar som fylls i på en ny ansökan (dagens datum plus så här många månader). Befintliga ansökningar ändras inte."
            ))

            labeledRow(language.text("Deadline after (months)", "Sista ansökningsdag efter (månader)")) {
                TextField("", value: intBinding(\.newApplicationClosesAfterMonths, default: WorkflowDefaultSettings.defaultClosesAfterMonths), format: .number)
                    .frame(width: 120)
                    .appTextInputChrome(fillsWidth: false)
            }
            effect(language.text(
                "Affects: the deadline filled in on a new application (today plus this many months).",
                "Påverkar: sista ansökningsdag som fylls i på en ny ansökan (dagens datum plus så här många månader)."
            ))

            labeledRow(language.text("Currency", "Valuta")) {
                AppMenuSelectionField(
                    selection: Binding(
                        get: { draft.resolvedCurrency },
                        set: { draft.newApplicationCurrency = $0 }
                    ),
                    options: draft.currencyPickerOptions(including: nil).map { ($0, $0) }
                )
                .frame(width: 200, alignment: .leading)
            }
            effect(language.text(
                "Affects: the currency a new application starts with.",
                "Påverkar: vilken valuta en ny ansökan får från början."
            ))

            labeledRow(language.text("Status", "Status")) {
                AppMenuSelectionField(
                    selection: Binding(
                        get: { draft.resolvedStatus },
                        set: { draft.newApplicationStatus = $0 }
                    ),
                    options: WorkflowDefaultSettings.selectableStatusOptions.map { (language.localizedStatus($0), $0) }
                )
                .frame(width: 200, alignment: .leading)
            }
            effect(language.text(
                "Affects: the status a new application starts with.",
                "Påverkar: vilken status en ny ansökan får från början."
            ))
        }
    }

    private var currencyCard: some View {
        card {
            header(
                language.text("Currencies to choose from", "Valutor att välja mellan"),
                resetTitle: language.text("Reset", "Återställ")
            ) {
                draft.currencyOptions = nil
                currencyListText = WorkflowDefaultSettings.defaultCurrencyOptions.joined(separator: ", ")
            }

            explanation(language.text(
                "Currency codes offered in the application form, separated by commas. Amounts are still converted to and summed in SEK.",
                "Valutakoder som erbjuds i ansökningsformuläret, åtskilda med kommatecken. Belopp räknas fortfarande om till och summeras i SEK."
            ))

            TextField("SEK, EUR, USD, NOK", text: $currencyListText)
                .appTextInputChrome()
                .onChange(of: currencyListText) { _, newValue in
                    guard hasLoaded else { return }
                    draft.currencyOptions = WorkflowDefaultSettings.currencyList(fromText: newValue)
                }
            effect(language.text(
                "Affects: the list in the Currency menu on an application and in \"New applications\" above. An application keeps its own currency even if it is removed from the list.",
                "Påverkar: listan i menyn Valuta på en ansökan och under Nya ansökningar ovan. En ansökan behåller sin valuta även om den tas bort ur listan."
            ))
        }
    }

    private var amountBucketCard: some View {
        card {
            header(
                language.text("Amount groups", "Beloppsgrupper"),
                resetTitle: language.text("Reset", "Återställ")
            ) {
                draft.amountBucketLowerLimit = nil
                draft.amountBucketUpperLimit = nil
            }

            explanation(language.text(
                "Applications are grouped as small, medium and large by the amount in SEK. The upper limit must be larger than the lower limit.",
                "Ansökningar delas in i små, mellanstora och stora efter beloppet i SEK. Den övre gränsen måste vara större än den nedre."
            ))

            labeledRow(language.text("Lower limit (SEK)", "Nedre gräns (kr)")) {
                TextField("", value: doubleBinding(\.amountBucketLowerLimit, default: WorkflowDefaultSettings.defaultAmountBucketLowerLimit), format: .number)
                    .frame(width: 160)
                    .appTextInputChrome(fillsWidth: false)
            }

            labeledRow(language.text("Upper limit (SEK)", "Övre gräns (kr)")) {
                TextField("", value: doubleBinding(\.amountBucketUpperLimit, default: WorkflowDefaultSettings.defaultAmountBucketUpperLimit), format: .number)
                    .frame(width: 160)
                    .appTextInputChrome(fillsWidth: false)
            }

            Text(language.text("Groups: ", "Grupper: ") + ApplicationAmountBucket.allCases.map { draft.amountBucketLabel($0) }.joined(separator: "   ·   "))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            effect(language.text(
                "Affects: the Amount groups table under Statistics > Grants, which shows per group the number of applications, how many were granted and the granted sum. An application is placed in a group by its maximum or approximate amount (otherwise the granted or applied amount).",
                "Påverkar: tabellen Beloppsgrupper under Statistik > Anslag, som visar per grupp antal ansökningar, hur många som beviljades och beviljad summa. En ansökan hamnar i en grupp efter sitt maxbelopp eller ungefärliga belopp (annars beviljat eller sökt belopp)."
            ))
        }
    }

    // MARK: Teaching

    private var teachingCard: some View {
        card {
            header(
                language.text("Programme and term", "Program och termin"),
                resetTitle: language.text("Reset", "Återställ")
            ) {
                draft.defaultTeachingProgramSv = nil
                draft.defaultTeachingProgramEn = nil
                draft.clinicalTeachingOrganizationWords = nil
                draft.teachingTermWordSv = nil
                draft.teachingTermWordEn = nil
                clinicalWordsText = WorkflowDefaultSettings.defaultClinicalTeachingOrganizationWords.joined(separator: ", ")
            }

            explanation(language.text(
                "Used only for courses where no programme has been written. A course with a term is placed under the standard programme.",
                "Används bara för kurser där inget program har skrivits in. En kurs med termin placeras under standardprogrammet."
            ))

            VStack(alignment: .leading, spacing: SettingsBilingualLayout.rowSpacing) {
                SettingsBilingualColumnsHeader(language: language)
                SettingsBilingualPairRow(title: language.text("Standard programme", "Standardprogram")) {
                    SettingsGrowingTextField(
                        placeholder: WorkflowDefaultSettings.defaultTeachingProgramSv,
                        text: textBinding(\.defaultTeachingProgramSv, default: WorkflowDefaultSettings.defaultTeachingProgramSv)
                    )
                } english: {
                    SettingsGrowingTextField(
                        placeholder: WorkflowDefaultSettings.defaultTeachingProgramEn,
                        text: textBinding(\.defaultTeachingProgramEn, default: WorkflowDefaultSettings.defaultTeachingProgramEn)
                    )
                }
            }

            effect(language.text(
                "Affects: the programme a course without its own programme is grouped under in Teaching (the programme list and filter) and in teaching exports. The Swedish name is shown when the app is in Swedish, the English one when it is in English.",
                "Påverkar: vilket program en kurs utan eget program hamnar under i Undervisning (programlistan och filtret) och i exporter av undervisning. Det svenska namnet visas när appen är på svenska, det engelska när den är på engelska."
            ))

            VStack(alignment: .leading, spacing: SettingsBilingualLayout.rowSpacing) {
                SettingsBilingualColumnsHeader(language: language)
                SettingsBilingualPairRow(title: language.text("Word for term", "Ord för termin")) {
                    SettingsGrowingTextField(
                        placeholder: WorkflowDefaultSettings.defaultTeachingTermWordSv,
                        text: textBinding(\.teachingTermWordSv, default: WorkflowDefaultSettings.defaultTeachingTermWordSv)
                    )
                } english: {
                    SettingsGrowingTextField(
                        placeholder: WorkflowDefaultSettings.defaultTeachingTermWordEn,
                        text: textBinding(\.teachingTermWordEn, default: WorkflowDefaultSettings.defaultTeachingTermWordEn)
                    )
                }
            }

            explanation(language.text(
                "When a course has a Swedish term such as \"\(draft.resolvedTeachingTermWordSv) 6\" but no English term, the English term becomes \"\(draft.resolvedTeachingTermWordEn) 6\".",
                "När en kurs har en svensk termin som \"\(draft.resolvedTeachingTermWordSv) 6\" men ingen engelsk, blir den engelska \"\(draft.resolvedTeachingTermWordEn) 6\"."
            ))

            effect(language.text(
                "Affects: the English term the app fills in on courses that lack one (when teaching data is loaded or changed). It is shown when the app is in English and in English exports. Courses with their own English term are not changed.",
                "Påverkar: den engelska termin som appen fyller i på kurser som saknar en (när undervisningsdata läses in eller ändras). Den visas när appen är på engelska och i engelska exporter. Kurser med egen engelsk termin ändras inte."
            ))
        }
    }

    // MARK: Export

    private var teachingMeritsCard: some View {
        card {
            header(
                language.text("Teaching merits", "Pedagogiska meriter"),
                resetTitle: language.text("Reset texts", "Återställ texter")
            ) {
                draft.teachingMeritsFacultyName = nil
                draft.principalSupervisionMonths = nil
                draft.principalSupervisionHours = nil
                draft.principalSupervisionMaxHours = nil
                draft.assistantSupervisionMonths = nil
                draft.assistantSupervisionHours = nil
                draft.assistantSupervisionMaxHours = nil
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Word template", "Wordmall"))
                    .appTypography(.fieldLabel)
                Text(teachingMeritsTemplatePath.nonEmpty ?? language.text("Built-in template", "Inbyggd mall"))
                    .appTypography(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppPalette.secondaryCardSurface)
                    )
                HStack(spacing: 10) {
                    Button(language.text("Choose file…", "Välj fil…")) {
                        chooseTeachingMeritsTemplate()
                    }
                    .buttonStyle(.bordered)
                    Button(language.text("Use built-in template", "Använd inbyggd mall")) {
                        setTeachingMeritsTemplatePath(nil)
                    }
                    .buttonStyle(.bordered)
                    .disabled(teachingMeritsTemplatePath.nonEmpty == nil)
                }
                if let path = teachingMeritsTemplatePath.nonEmpty, !FileManager.default.fileExists(atPath: path) {
                    Text(language.text("The file cannot be found. The built-in template is used instead.", "Filen hittas inte. Den inbyggda mallen används i stället."))
                        .appTypography(.secondary)
                        .foregroundStyle(AppPalette.vividRed)
                }
                effect(language.text(
                    "Affects: the Word file the Teaching merits export is filled into. The built-in template is used when no file is chosen or the file is missing.",
                    "Påverkar: vilken Wordfil exporten Pedagogiska meriter fylls i på. Den inbyggda mallen används när ingen fil är vald eller filen saknas."
                ))
            }

            labeledRow(language.text("Faculty", "Fakultet")) {
                TextField(language.text("Name of the faculty", "Fakultetens namn"), text: textBinding(\.teachingMeritsFacultyName, default: WorkflowDefaultSettings.defaultTeachingMeritsFacultyName))
                    .appTextInputChrome()
            }

            effect(language.text(
                "Affects: the heading of the Teaching merits export and its preview, when the built-in template is used. Without a faculty the heading names none. A template file of your own is not changed.",
                "Påverkar: rubriken i exporten Pedagogiska meriter och dess förhandsvisning, när den inbyggda mallen används. Utan fakultet nämner rubriken ingen. En egen mallfil ändras inte."
            ))

            supervisionRuleRow(
                title: language.text("Main supervisor", "Huvudhandledare"),
                months: \.principalSupervisionMonths,
                defaultMonths: WorkflowDefaultSettings.defaultPrincipalSupervisionMonths,
                hours: \.principalSupervisionHours,
                defaultHours: WorkflowDefaultSettings.defaultPrincipalSupervisionHours,
                maxHours: \.principalSupervisionMaxHours,
                defaultMaxHours: WorkflowDefaultSettings.defaultPrincipalSupervisionMaxHours
            )

            supervisionRuleRow(
                title: language.text("Co-supervisor", "Bihandledare"),
                months: \.assistantSupervisionMonths,
                defaultMonths: WorkflowDefaultSettings.defaultAssistantSupervisionMonths,
                hours: \.assistantSupervisionHours,
                defaultHours: WorkflowDefaultSettings.defaultAssistantSupervisionHours,
                maxHours: \.assistantSupervisionMaxHours,
                defaultMaxHours: WorkflowDefaultSettings.defaultAssistantSupervisionMaxHours
            )

            explanation(language.text(
                "The rules are written in the table headings of the export: \"\(draft.doctoralSupervisionTitle(principal: true))\". The hours themselves come from each doctoral student's supervision periods.",
                "Reglerna skrivs i tabellrubrikerna i exporten: \"\(draft.doctoralSupervisionTitle(principal: true))\". Själva timmarna hämtas från varje doktorands handledningsperioder."
            ))

            effect(language.text(
                "Affects: the table headings for doctoral supervision in the Teaching merits export, and the suggested number of hours shown on a doctoral student (months you have supervised, converted by these rules and capped at the maximum).",
                "Påverkar: tabellrubrikerna för doktorandhandledning i exporten Pedagogiska meriter, och förslaget på antal timmar som visas på en doktorand (de månader du handlett, omräknade med dessa regler och högst maxtaket)."
            ))
        }
    }

    private func supervisionRuleRow(
        title: String,
        months: WritableKeyPath<WorkflowDefaultSettings, Int?>,
        defaultMonths: Int,
        hours: WritableKeyPath<WorkflowDefaultSettings, Double?>,
        defaultHours: Double,
        maxHours: WritableKeyPath<WorkflowDefaultSettings, Double?>,
        defaultMaxHours: Double
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .appTypography(.fieldLabel)
                .frame(width: 150, alignment: .leading)
            TextField("", value: intBinding(months, default: defaultMonths), format: .number)
                .frame(width: 60)
                .appTextInputChrome(fillsWidth: false)
            Text(language.text("months full time equal", "månader på heltid motsvarar"))
            TextField("", value: doubleBinding(hours, default: defaultHours), format: .number)
                .frame(width: 70)
                .appTextInputChrome(fillsWidth: false)
            Text(language.text("hours, at most", "timmar, högst"))
            TextField("", value: doubleBinding(maxHours, default: defaultMaxHours), format: .number)
                .frame(width: 80)
                .appTextInputChrome(fillsWidth: false)
            Text(language.text("hours per doctoral student", "timmar per doktorand"))
            Spacer(minLength: 0)
        }
    }

    private var statementTemplatesCard: some View {
        card {
            header(
                language.text("Funding and ethics texts", "Texter om finansiering och etik"),
                resetTitle: language.text("Reset texts", "Återställ texter")
            ) {
                draft.fundingStatementTemplateEn = nil
                draft.fundingStatementTemplateSv = nil
                draft.ethicsHelsinkiTemplateEn = nil
                draft.ethicsHelsinkiTemplateSv = nil
                draft.ethicsApprovalTemplateEn = nil
                draft.ethicsApprovalTemplateSv = nil
                draft.ethicsTrialTemplateEn = nil
                draft.ethicsTrialTemplateSv = nil
            }

            explanation(language.text(
                "Texts copied from a publication. Words in curly brackets are replaced when the text is copied: {funders} becomes the list of grant givers, {dnr} the ethics case numbers and {trial} the ClinicalTrials.gov numbers. An empty field returns to the standard text.",
                "Texter som kopieras från en publikation. Ord inom klammerparentes byts ut när texten kopieras: {funders} blir listan över anslagsgivare, {dnr} etikdiarienumren och {trial} numren i ClinicalTrials.gov. Ett tomt fält återgår till standardtexten."
            ))

            effect(language.text(
                "Affects: the text put on the clipboard when you copy the funding statement from a publication or a project, and the ethics statement from a publication. The Swedish text is used when you copy in Swedish, the English text when you copy in English.",
                "Påverkar: texten som läggs i urklipp när du kopierar finansieringstexten från en publikation eller ett projekt, och etiktexten från en publikation. Den svenska texten används när du kopierar på svenska, den engelska när du kopierar på engelska."
            ))

            VStack(alignment: .leading, spacing: SettingsBilingualLayout.rowSpacing) {
                SettingsBilingualColumnsHeader(language: language)
                templatePairRow(
                    language.text("Funding", "Finansiering"),
                    swedish: \.fundingStatementTemplateSv,
                    swedishDefault: WorkflowDefaultSettings.defaultFundingStatementTemplateSv,
                    english: \.fundingStatementTemplateEn,
                    englishDefault: WorkflowDefaultSettings.defaultFundingStatementTemplateEn
                )
                templatePairRow(
                    language.text("Ethics without approval number", "Etik utan diarienummer"),
                    swedish: \.ethicsHelsinkiTemplateSv,
                    swedishDefault: WorkflowDefaultSettings.defaultEthicsHelsinkiTemplateSv,
                    english: \.ethicsHelsinkiTemplateEn,
                    englishDefault: WorkflowDefaultSettings.defaultEthicsHelsinkiTemplateEn
                )
                templatePairRow(
                    language.text("Ethics approval", "Etiktillstånd"),
                    swedish: \.ethicsApprovalTemplateSv,
                    swedishDefault: WorkflowDefaultSettings.defaultEthicsApprovalTemplateSv,
                    english: \.ethicsApprovalTemplateEn,
                    englishDefault: WorkflowDefaultSettings.defaultEthicsApprovalTemplateEn
                )
                templatePairRow(
                    language.text("Trial registration", "Studieregistrering"),
                    swedish: \.ethicsTrialTemplateSv,
                    swedishDefault: WorkflowDefaultSettings.defaultEthicsTrialTemplateSv,
                    english: \.ethicsTrialTemplateEn,
                    englishDefault: WorkflowDefaultSettings.defaultEthicsTrialTemplateEn
                )
            }
        }
    }

    /// One Swedish/English row of statement templates. The fields grow to
    /// show the whole text.
    private func templatePairRow(
        _ title: String,
        swedish swedishKeyPath: WritableKeyPath<WorkflowDefaultSettings, String?>,
        swedishDefault: String,
        english englishKeyPath: WritableKeyPath<WorkflowDefaultSettings, String?>,
        englishDefault: String
    ) -> some View {
        SettingsBilingualPairRow(title: title) {
            SettingsGrowingTextField(
                placeholder: swedishDefault,
                text: textBinding(swedishKeyPath, default: swedishDefault),
                minimumLines: 2
            )
        } english: {
            SettingsGrowingTextField(
                placeholder: englishDefault,
                text: textBinding(englishKeyPath, default: englishDefault),
                minimumLines: 2
            )
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        AppSettingsCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
        }
    }

    private func header(_ title: String, resetTitle: String, reset: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .appTypography(.sectionTitle)
            Spacer()
            AppResetButton(title: resetTitle, action: reset)
        }
    }

    /// The "Affects: …" line under a setting.
    private func effect(_ text: String) -> some View {
        SettingsEffectNote(text)
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func labeledRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .appTypography(.fieldLabel)
                .frame(width: 260, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func intBinding(_ keyPath: WritableKeyPath<WorkflowDefaultSettings, Int?>, default defaultValue: Int) -> Binding<Int> {
        Binding(
            get: { draft[keyPath: keyPath] ?? defaultValue },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<WorkflowDefaultSettings, Double?>, default defaultValue: Double) -> Binding<Double> {
        Binding(
            get: { draft[keyPath: keyPath] ?? defaultValue },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func textBinding(_ keyPath: WritableKeyPath<WorkflowDefaultSettings, String?>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? defaultValue },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    // MARK: Loading and saving

    private func load() {
        let settings = store.workflowDefaultSettings
        draft = settings
        currencyListText = settings.resolvedCurrencyOptions.joined(separator: ", ")
        clinicalWordsText = settings.resolvedClinicalTeachingOrganizationWords.joined(separator: ", ")
        teachingMeritsTemplatePath = UserDefaults.standard.string(forKey: Self.teachingMeritsTemplateDefaultsKey) ?? ""
        hasLoaded = true
    }

    private func scheduleSave(_ settings: WorkflowDefaultSettings) {
        guard hasLoaded else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            store.autosaveWorkflowDefaultSettings(settings)
        }
    }

    static var teachingMeritsTemplateDefaultsKey: String {
        AppRuntime.scopedDefaultsKey("TeachingMeritsTemplatePath")
    }

    private func setTeachingMeritsTemplatePath(_ path: String?) {
        if let path = path?.trimmedOrNil {
            UserDefaults.standard.set(path, forKey: Self.teachingMeritsTemplateDefaultsKey)
            teachingMeritsTemplatePath = path
        } else {
            UserDefaults.standard.removeObject(forKey: Self.teachingMeritsTemplateDefaultsKey)
            teachingMeritsTemplatePath = ""
        }
    }

    private func chooseTeachingMeritsTemplate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let docxType = UTType(filenameExtension: "docx") {
            panel.allowedContentTypes = [docxType]
        }
        if let current = teachingMeritsTemplatePath.nonEmpty {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        }
        panel.prompt = language.text("Choose", "Välj")
        panel.title = language.text("Choose Word template for teaching merits", "Välj Wordmall för pedagogiska meriter")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setTeachingMeritsTemplatePath(url.path)
    }
}
