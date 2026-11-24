import SwiftUI

struct ConnectionsView: View {
    let appleHealth: HealthKitEHRService
    @Bindable var direct: DirectFHIRService
    @Environment(\.openURL) private var openURL
    @State private var couldNotOpenAppleHealth = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                appleHealthCard
                directCard
            }
            .frame(maxWidth: 680)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Connections")
        .alert("Apple Health could not open", isPresented: $couldNotOpenAppleHealth) {
            Button("OK", role: .cancel) {}
        }
    }

    private var appleHealthCard: some View {
        SourceCard(
            title: "Apple Health Clinical Records",
            subtitle: "Read records from the local store",
            icon: "heart.text.square.fill", tint: .pink
        ) {
            Text("Choose which clinical records to share. The app reads them on this device and keeps them separate from the EHR portal.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            StatusPill(
                label: appleHealth.authorizationRequested ? "Authorization Requested" : "Not Connected",
                icon: appleHealth.authorizationRequested ? "checkmark.circle" : "circle.dashed", tint: .pink
            )

            Button {
                Task {
                    await appleHealth.requestAuthorization()
                    if appleHealth.authorizationRequested {
                        await appleHealth.fetchAllClinicalRecords()
                    }
                }
            } label: {
                HStack {
                    if appleHealth.isLoading { ProgressView().tint(.white) }
                    Text("Connect Apple Health Records")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.pink)
            .disabled(appleHealth.isLoading)

            Button {
                if let url = URL(string: "x-apple-health://") {
                    openURL(url) { accepted in couldNotOpenAppleHealth = !accepted }
                }
            } label: {
                Label("Open Apple Health App", systemImage: "arrow.up.right")
            }
            .tint(.pink)

            if HealthKitEHRService.supportsSimulatorSamples {
                Toggle("Load Simulator Sample Records", isOn: Binding(
                    get: { appleHealth.isUsingSampleData },
                    set: { enabled in Task { await appleHealth.setSimulatorSamples(enabled) } }
                ))
                .font(.subheadline)
                .tint(.pink)
                .disabled(appleHealth.isLoading)
            }
            if let error = appleHealth.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var directCard: some View {
        SourceCard(
            title: "Direct EHR Integration",
            subtitle: "SMART on FHIR R4",
            icon: "network", tint: .blue
        ) {
            Picker("EHR Sandbox", selection: Binding(
                get: { direct.environment }, set: { direct.selectEnvironment($0) }
            )) {
                ForEach(FHIRSandboxEnvironment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .disabled(direct.isSigningIn || direct.isSignedIn)

            if direct.isSignedIn {
                connectedSession
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Client ID").font(.subheadline.weight(.medium))
                    TextField("Registered sandbox client ID", text: $direct.clientID)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Client ID")
                    if direct.environment != .smartHealthIT {
                        Text("Use a public sandbox client registered with ehr-demo://oauth-callback.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(direct.isSigningIn)

                if direct.environment.supportsWriteRequest {
                    Toggle("Enable sample vital writes", isOn: $direct.requestWriteAccess)
                        .font(.subheadline)
                        .disabled(direct.isSigningIn)
                } else {
                    Text("This patient sandbox advertises read access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await direct.signIn(environment: direct.environment) }
                } label: {
                    HStack {
                        if direct.isSigningIn { ProgressView().tint(.white) }
                        Text("Sign in with EHR Portal")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
                .disabled(direct.isSigningIn || direct.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error = direct.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var connectedSession: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusPill(label: "Connected", icon: "checkmark.circle.fill", tint: .blue)

            VStack(alignment: .leading, spacing: 8) {
                if let patientID = direct.patientID {
                    LabeledContent("Patient ID") {
                        Text(patientID).font(.system(.footnote, design: .monospaced))
                    }
                }
                if let expiration = direct.expiration {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        LabeledContent("Token expires") {
                            if expiration > context.date {
                                Text(timerInterval: context.date...expiration, countsDown: true)
                                    .monospacedDigit()
                                    .multilineTextAlignment(.trailing)
                            } else {
                                Text("Expired").foregroundStyle(.red)
                            }
                        }
                    }
                }
                if let scopes = direct.scopes {
                    Text("Granted scopes").font(.subheadline.weight(.medium))
                    Text(scopes)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.subheadline)

            Button("Disconnect", role: .destructive) { direct.disconnect() }
                .buttonStyle(.bordered)
                .disabled(direct.isPosting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}
