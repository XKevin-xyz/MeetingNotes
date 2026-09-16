import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsDashboardView: View {
    @Environment(AppStorageManager.self) private var storage
    @State private var showDeleteConfirmation = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoTranscribe") private var autoTranscribe = false
    @AppStorage("skipSilence") private var skipSilence = true
    @AppStorage("preferredLanguage") private var preferredLanguage = "nl"
    @AppStorage("transcriptionQuality") private var transcriptionQuality = "base"
    @AppStorage("cloudProcessing") private var cloudProcessing = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    @State private var loginItemMessage = ""
    @State private var updateChecker = UpdateChecker()

    var body: some View {
        TabView {
            Form {
                Section("Starten") {
                    Toggle("Start MeetingNotes bij inloggen", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            updateLoginItem(enabled: enabled)
                        }
                    Toggle("Automatisch transcriberen na opname", isOn: $autoTranscribe)
                    if !loginItemMessage.isEmpty {
                        Text(loginItemMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Interface") {
                    Text("De app volgt momenteel automatisch het uiterlijk van macOS.")
                        .foregroundStyle(.secondary)
                    Button("Welkomstuitleg opnieuw tonen") {
                        hasSeenOnboarding = false
                    }
                }
                UpdateSettingsSection(checker: updateChecker)
            }
            .formStyle(.grouped)
            .tabItem { Label("Algemeen", systemImage: "gearshape") }

            Form {
                AudioSettingsSection()
                Section("Toegang") {
                    Text("MeetingNotes gebruikt microfoon- en scherm-/systeemaudiotoegang om gesprekken uit iedere vergaderapp op te nemen.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Audio", systemImage: "mic") }

            Form {
                Section("Transcriptie") {
                    Picker("Taal", selection: $preferredLanguage) {
                        Text("Nederlands").tag("nl")
                        Text("English").tag("en")
                    }
                    Picker("Kwaliteit", selection: $transcriptionQuality) {
                        Text("Snel — tiny").tag("tiny")
                        Text("Gebalanceerd — base").tag("base")
                        Text("Beste kwaliteit").tag("large")
                    }
                    Toggle("Stiltes automatisch overslaan", isOn: $skipSilence)
                }
                Section("Modellen") {
                    LabeledContent("Modelopslag", value: storage.modelsURL.path)
                    Button("Open modellen in Finder") {
                        storage.reveal(storage.modelsURL)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Transcriptie", systemImage: "text.bubble") }

            Form {
                Section("Lokale opslag") {
                    LabeledContent("Vergaderdata", value: storage.formattedDataSize)
                    LabeledContent("Locatie", value: storage.rootURL.path)
                    Button("Open opslag in Finder") {
                        storage.revealRootInFinder()
                    }
                }
                Section("Verwijderen") {
                    Button("Alle gegevens verwijderen", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    Text("Verwijdert opnames, transcripties, modellen, exports en caches. De app zelf blijft geïnstalleerd.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Opslag", systemImage: "internaldrive") }

            Form {
                Section("Verwerking") {
                    Toggle("Lokale verwerking gebruiken", isOn: Binding(
                        get: { !cloudProcessing },
                        set: { cloudProcessing = !$0 }
                    ))
                    Text("De huidige transcriptie-engine verwerkt alles lokaal. Cloudproviders worden pas toegevoegd wanneer je daar bewust voor kiest.")
                        .foregroundStyle(.secondary)
                }
                Section("Toestemming") {
                    Text("Informeer alle deelnemers voordat je een vergadering opneemt of transcribeert. Controleer de regels die voor jouw situatie gelden.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .padding(8)
        .frame(width: 720, height: 500)
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

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                loginItemMessage = "MeetingNotes start voortaan mee met macOS."
            } else {
                try SMAppService.mainApp.unregister()
                loginItemMessage = "Automatisch starten is uitgeschakeld."
            }
        } catch {
            loginItemMessage = "Dit werkt pas in de ondertekende app-versie, niet vanuit `swift run`."
        }
    }
}

private struct AudioSettingsSection: View {
    @AppStorage("microphoneDeviceID") private var microphoneDeviceID = ""
    @State private var testMessage = ""

    private var microphones: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    var body: some View {
        Section("Audio") {
            Picker("Microfoon", selection: $microphoneDeviceID) {
                Text("Systeemstandaard").tag("")
                ForEach(microphones, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID)
                }
            }

            LabeledContent("Systeemaudio", value: "Huidig uitvoerapparaat")

            Button("Test microfoon") {
                Task {
                    let granted = await AVCaptureDevice.requestAccess(for: .audio)
                    testMessage = granted ? "Microfoontoegang is beschikbaar." : "Microfoontoegang is geweigerd."
                }
            }

            if !testMessage.isEmpty {
                Text(testMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct UpdateSettingsSection: View {
    @Bindable var checker: UpdateChecker

    var body: some View {
        Section("Updates") {
            LabeledContent("Huidige versie", value: "(checker.currentVersion) (build (checker.currentBuild))")

            switch checker.state {
            case .idle:
                Text("Controleer of er een nieuwe MeetingNotes-versie beschikbaar is.")
                    .foregroundStyle(.secondary)
            case .checking:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Controleren op updates…")
                        .foregroundStyle(.secondary)
                }
            case .notConfigured:
                Text("De updatebron wordt ingesteld zodra de publieke repository beschikbaar is.")
                    .foregroundStyle(.secondary)
            case .upToDate:
                Label("Je gebruikt de nieuwste versie.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .available(update):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Versie \(update.version) beschikbaar", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    if let notes = update.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Download update") {
                        checker.openDownload(update)
                    }
                    .buttonStyle(.borderedProminent)
                }
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Button("Controleer op updates") {
                Task { await checker.check() }
            }
            .disabled(isChecking)
        }
    }

    private var isChecking: Bool {
        if case .checking = checker.state { return true }
        return false
    }
}
