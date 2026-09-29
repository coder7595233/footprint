import SwiftUI

struct PublicationMetricYearOptionRow: View {
    let title: String
    @Binding var isOn: Bool
    @Binding var yearMode: PublicationMetricYearMode
    let language: AppLanguage

    private var yearModeOptions: [(label: String, value: PublicationMetricYearMode)] {
        PublicationMetricYearMode.allCases.map { mode in
            (mode.displayName(language: language), mode)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(title, isOn: $isOn)
                .appCheckboxStyle()
            Spacer(minLength: 12)
            if isOn {
                if AppRuntime.usesRenewedChrome {
                    AppMenuSelectionField(
                        selection: $yearMode,
                        options: yearModeOptions,
                        placeholder: nil
                    )
                    .frame(width: 190)
                } else {
                    Picker("", selection: $yearMode) {
                        ForEach(PublicationMetricYearMode.allCases) { mode in
                            Text(mode.displayName(language: language)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Journal metrics from": sets the year choice for JIF, quartile and the
/// Norwegian list at once. The publication year falls back to the latest
/// registered year when that year has no value.
struct JournalMetricsSourceRow: View {
    @Binding var options: PublicationExportOptions
    let language: AppLanguage

    private var selection: Binding<PublicationMetricYearMode?> {
        Binding(
            get: {
                let modes = Set([options.impactFactorYearMode, options.quartileYearMode, options.norwegianListYearMode])
                return modes.count == 1 ? modes.first : nil
            },
            set: { newValue in
                guard let newValue else { return }
                options.impactFactorYearMode = newValue
                options.quartileYearMode = newValue
                options.norwegianListYearMode = newValue
            }
        )
    }

    private var choices: [(label: String, value: PublicationMetricYearMode?)] {
        PublicationMetricYearMode.allCases.map { mode in
            (mode.displayName(language: language), Optional(mode))
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(language.text("Journal metrics from", "Tidskriftsmått från"))
            Spacer(minLength: 12)
            AppMenuSelectionField(
                selection: selection,
                options: choices,
                placeholder: language.text("Different per metric", "Olika per mått")
            )
            .frame(width: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
