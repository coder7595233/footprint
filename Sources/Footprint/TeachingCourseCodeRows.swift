import SwiftUI

/// F7: a course can carry several codes after one another. The row without an
/// end date is the current one, and is what lists and exports show.
struct TeachingCourseCodeRows: View {
    @Binding var entries: [TeachingCourseCodeEntry]
    let language: AppLanguage
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, _ in
                HStack(spacing: 6) {
                    TextField(language.text("Course code", "Kurskod"), text: binding(index, \.code))
                        .appTextInputChrome()
                        .frame(width: 104)
                    TextField(language.text("From", "Från"), text: binding(index, \.validFrom))
                        .appTextInputChrome()
                        .frame(width: 96)
                    TextField(language.text("To", "Till"), text: binding(index, \.validTo))
                        .appTextInputChrome()
                        .frame(width: 96)
                    Button {
                        guard entries.indices.contains(index) else { return }
                        entries.remove(at: index)
                        onCommit()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help(language.text("Remove course code", "Ta bort kurskod"))
                }
            }
            Button {
                entries.append(TeachingCourseCodeEntry())
                onCommit()
            } label: {
                Text(language.text("Add course code", "Lägg till kurskod"))
                    .appTypography(.tableHeader)
            }
            .buttonStyle(.plain)
        }
    }

    private func binding(_ index: Int, _ key: WritableKeyPath<TeachingCourseCodeEntry, String>) -> Binding<String> {
        Binding(
            get: { entries.indices.contains(index) ? entries[index][keyPath: key] : "" },
            set: { newValue in
                guard entries.indices.contains(index) else { return }
                entries[index][keyPath: key] = newValue
            }
        )
    }
}
