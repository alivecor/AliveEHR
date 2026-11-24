import SwiftUI

struct DirectFHIRRecordsView: View {
    let service: DirectFHIRService
    let openConnections: () -> Void
    @State private var category = ClinicalCategory.all
    @State private var showsPostSheet = false

    var body: some View {
        VStack(spacing: 10) {
            header.padding(.horizontal, 20)
            CategoryFilterBar(selection: $category, tint: .blue)
            ClinicalRecordsList(
                records: service.records, category: category, provenance: .directFHIR,
                showsSkeleton: service.isLoading
            ) {
                if !service.isSignedIn {
                    ContentUnavailableView {
                        Label("Connect an EHR sandbox", systemImage: "network.slash")
                    } description: {
                        Text("Sign in with an EHR portal in Connections to fetch patient records.")
                    } actions: {
                        Button("Go to Connections", action: openConnections).buttonStyle(.bordered)
                    }
                } else {
                    ContentUnavailableView {
                        Label(
                            service.records.isEmpty ? "No records available" : "No records in this category",
                            systemImage: "tray"
                        )
                    } description: {
                        if service.records.isEmpty { Text("Pull down to query the sandbox again.") }
                    }
                }
            }
            .refreshable { await service.fetchPatientResources() }
        }
        .padding(.top, 8)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Direct EHR")
        .tint(.blue)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsPostSheet = true
                } label: {
                    Label("Post Vital", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(!service.isSignedIn || service.isLoading || service.isPosting)
            }
        }
        .sheet(isPresented: $showsPostSheet) {
            PostVitalSheet(service: service, openConnections: {
                showsPostSheet = false
                openConnections()
            })
        }
        .onChange(of: service.isSignedIn) { _, signedIn in
            if !signedIn {
                category = .all
                showsPostSheet = false
            }
        }
        .task(id: service.isSignedIn) {
            if service.isSignedIn && service.records.isEmpty && service.measurement == nil {
                await service.fetchPatientResources()
            }
        }
    }

    private var header: some View {
        SourceCard(
            title: "Source: Direct FHIR R4 API",
            subtitle: service.isSignedIn ? service.environment.rawValue : "No portal session",
            icon: "network", tint: .blue
        ) {
            if service.isLoading {
                ProgressView("Querying the sandbox…")
                    .font(.footnote)
            } else if let measurement = service.measurement {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { requestBadges(measurement) }
                    VStack(alignment: .leading, spacing: 6) { requestBadges(measurement) }
                }
            }
            if let error = service.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private func requestBadges(_ measurement: HTTPMeasurement) -> some View {
        let success = (200..<300).contains(measurement.status)
        StatusPill(label: measurement.label, icon: success ? "checkmark.circle" : "exclamationmark.circle", tint: success ? .green : .red)
        StatusPill(label: "\(measurement.milliseconds) ms", icon: "timer", tint: .blue)
    }
}
