import SwiftUI

struct ClinicalRecordsList<Empty: View>: View {
    let records: [ClinicalItem]
    let category: ClinicalCategory
    let provenance: DataProvenance
    var showsSkeleton = false
    @ViewBuilder let empty: Empty
    @State private var selected: ClinicalItem?

    var body: some View {
        let visible = category == .all ? records : records.filter { $0.category == category }
        List {
            if showsSkeleton {
                ForEach(0..<3, id: \.self) { index in
                    row(ClinicalRecordRow(item: skeleton(index)))
                        .redacted(reason: .placeholder)
                        .accessibilityHidden(true)
                }
            } else if visible.isEmpty {
                row(empty)
            } else {
                ForEach(visible) { item in
                    row(Button { selected = item } label: { ClinicalRecordRow(item: item) }
                        .buttonStyle(.plain))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .sheet(item: $selected) { RecordDetailSheet(item: $0) }
    }

    private func row<Content: View>(_ content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func skeleton(_ index: Int) -> ClinicalItem {
        ClinicalItem(
            id: "loading-\(index)", title: "Clinical record", subtitle: "Recorded value",
            referenceRange: nil, isAbnormal: false, date: .now, sourceName: "Source facility",
            category: .all, provenance: provenance, fhirVersion: "R4", rawJSON: ""
        )
    }
}
