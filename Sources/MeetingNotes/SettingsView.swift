import SwiftUI

struct SettingsView: View {
    @Environment(AppStorageManager.self) private var storage
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Opslag") {
                LabeledContent("Vergaderdata", value: storage.formattedDataSize)
                LabeledContent("Locatie", value: storage.rootURL.path)

                HStack {
                    Button("Open in Finder") {
                        storage.revealRootInFinder()
                    }
                    Button("Alle gegevens verwijderen", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }

            Section("Privacy") {
                Text("Opnames, transcripties en lokale modellen blijven op deze Mac tenzij je later bewust een cloudprovider inschakelt.")
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                Text("MeetingNotes — vroege ontwikkelversie")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 390)
        .confirmationDialog(
            "Alle lokale vergaderdata verwijderen?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Verwijder alles", role: .destructive) {
                storage.deleteAllUserData()
            }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Dit verwijdert opnames, transcripties, modellen, exports en caches. De app zelf blijft geïnstalleerd.")
        }
    }
}
