import SwiftUI

struct PostVitalSheet: View {
    let service: DirectFHIRService
    let openConnections: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var systolic = "120"
    @State private var diastolic = "80"
    @State private var posted = false
    @State private var requiresRefresh = false
    @State private var errorMessage: String?

    private var reading: (systolic: Int, diastolic: Int)? {
        guard let high = Int(systolic), let low = Int(diastolic),
              BloodPressureObservation.isValid(systolic: high, diastolic: low) else { return nil }
        return (high, low)
    }

    var body: some View {
        NavigationStack {
            Form {
                if posted {
                    Section {
                        Label("Observation submitted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let measurement = service.measurement {
                            Text("\(measurement.label) · \(measurement.milliseconds) ms").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        LabeledContent("Systolic") { pressureField("Systolic", value: $systolic) }
                        LabeledContent("Diastolic") { pressureField("Diastolic", value: $diastolic) }
                    } header: {
                        Text("Blood Pressure")
                    } footer: {
                        Text("Submit a sample reading to the selected EHR sandbox.")
                    }
                    .disabled(service.isPosting)

                    if !service.canPostObservation {
                        Section {
                            Text(service.environment.supportsWriteRequest
                                 ? SMARTError.writeScope.localizedDescription
                                 : "Choose a sandbox with Observation create access in Connections.")
                                .foregroundStyle(.secondary)
                            Button("Go to Connections", action: openConnections)
                        }
                    } else {
                        Section {
                            Button {
                                guard let reading else { return }
                                Task { await submit(reading) }
                            } label: {
                                if service.isPosting { ProgressView("Submitting…") }
                                else { Label("Submit Sample Observation", systemImage: "arrow.up.circle") }
                            }
                            .disabled(reading == nil || service.isPosting || requiresRefresh)
                        }
                    }

                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Post Vital")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(service.isPosting || posted || requiresRefresh)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(posted ? "Done" : "Close") {
                        dismiss()
                        if posted || requiresRefresh { Task { await service.fetchPatientResources() } }
                    }
                    .disabled(service.isPosting)
                }
            }
        }
    }

    private func pressureField(_ label: String, value: Binding<String>) -> some View {
        HStack(spacing: 8) {
            TextField(label, text: value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("\(label) pressure")
                .monospacedDigit()
            Text("mmHg").foregroundStyle(.secondary)
        }
    }

    private func submit(_ reading: (systolic: Int, diastolic: Int)) async {
        errorMessage = nil
        do {
            try await service.postSampleVitalObservation(systolic: reading.systolic, diastolic: reading.diastolic)
            posted = true
        } catch SMARTError.uncertainWrite {
            requiresRefresh = true
            errorMessage = SMARTError.uncertainWrite.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
