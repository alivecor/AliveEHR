import SwiftUI

struct AppleHealthRecordsView: View {
    let service: HealthKitEHRService
    let openConnections: () -> Void
    @State private var category = ClinicalCategory.all

    var body: some View {
        VStack(spacing: 10) {
            SourceCard(
                title: "Source: Apple Health Local Store",
                subtitle: "\(service.records.count) \(service.records.count == 1 ? "record" : "records")",
                icon: "heart.text.square.fill", tint: .pink
            ) {
                if service.isUsingSampleData {
                    StatusPill(label: "Simulator samples", icon: "iphone", tint: .orange)
                }
                if let date = service.lastSyncDate {
                    Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await service.fetchAllClinicalRecords() }
                } label: {
                    Label("Re-Query", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(service.isLoading || (!service.authorizationRequested && !service.isUsingSampleData))
                if let error = service.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)
            CategoryFilterBar(selection: $category, tint: .pink)
            ClinicalRecordsList(
                records: service.records, category: category, provenance: .appleHealth,
                showsSkeleton: service.isLoading && service.records.isEmpty
            ) {
                if !service.authorizationRequested && !service.isUsingSampleData {
                    ContentUnavailableView {
                        Label("Connect Apple Health", systemImage: "heart.text.square")
                    } description: {
                        Text("Request access to clinical records in Connections.")
                    } actions: {
                        Button("Go to Connections", action: openConnections).buttonStyle(.bordered)
                    }
                } else {
                    ContentUnavailableView(
                        service.records.isEmpty ? "No records available" : "No records in this category",
                        systemImage: "tray"
                    )
                }
            }
        }
        .padding(.top, 8)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Apple Health")
        .tint(.pink)
    }
}
