import SwiftUI

/// F25: the startup report dialog, kept out of AppShell's modifier chain so the
/// type checker does not have to carry it.
struct StartupReportAlertModifier: ViewModifier {
    @ObservedObject var store: GrantDataStore
    let language: AppLanguage

    private var isPresented: Binding<Bool> {
        Binding<Bool>(
            get: { store.startupReport != nil },
            set: { presented in
                if !presented {
                    store.startupReport = nil
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            language.text("Startup report", "Rapport från starten"),
            isPresented: isPresented,
            actions: {
                Button(language.text("OK", "OK")) {
                    store.startupReport = nil
                }
            },
            message: {
                Text(store.startupReport ?? "")
            }
        )
    }
}
