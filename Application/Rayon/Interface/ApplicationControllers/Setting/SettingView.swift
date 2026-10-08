import RayonModule
import RayonTerminal
import SwiftUI

struct SettingView: View {
    @EnvironmentObject var store: RayonStore

    var body: some View {
        GhosttyConfigurationView(embedded: true, hostSections: [
            ConfigHostSettingsSection(id: "rayon-general", title: "General", icon: "gearshape",
                keywords: "Reduced Effect Disable Confirmation Record Recent animation confirmation history") { general },
            ConfigHostSettingsSection(id: "rayon-connection", title: "Connection", icon: "network",
                keywords: "SSH timeout Server monitor interval connection") { connection },
        ])
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("General").font(.largeTitle.bold())
            Toggle("Reduced Effect", isOn: $store.reducedViewEffects)
                .font(.system(.headline, design: .rounded))
            Text("This option will remove animated blur background and star animation.")
                .font(.system(.subheadline, design: .rounded))
            Toggle("Disable Confirmation", isOn: $store.disableConformation)
                .font(.system(.headline, design: .rounded))
            Text("This option will remove the confirmation alert, use with caution.")
                .font(.system(.subheadline, design: .rounded))
            Toggle("Record Recent", isOn: $store.storeRecent)
                .font(.system(.headline, design: .rounded))
            Text("This option will save several most recent used machine.")
                .font(.system(.subheadline, design: .rounded))

        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection").font(.largeTitle.bold())
            Slider(value: Binding<Double>.init(get: {
                Double(store.timeout)
            }, set: { newValue in
                store.timeout = Int(newValue)
            }), in: 2 ... 30, step: 1) { Group {} }
            Text("SSH will report invalid connection after \(store.timeout) seconds.")
                .font(.system(.subheadline, design: .rounded))
            Slider(value: Binding<Double>.init(get: {
                Double(store.monitorInterval)
            }, set: { newValue in
                store.monitorInterval = Int(newValue)
            }), in: 5 ... 60, step: 5) { Group {} }
            Text("Server monitor will update information \(store.monitorInterval) seconds after last attempt.")
                .font(.system(.subheadline, design: .rounded))

        }
    }
}
