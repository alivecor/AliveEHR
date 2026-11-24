import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordDetailSheet: View {
    let item: ClinicalItem
    @Environment(\.dismiss) private var dismiss
    @State private var section = Section.summary
    @State private var copied = false

    private enum Section: String, CaseIterable {
        case summary = "Clinical Summary"
        case raw = "Raw FHIR JSON"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Record view", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                if section == .summary {
                    Form {
                        SwiftUI.Section(item.title) {
                            LabeledContent {
                                Text(item.subtitle)
                                    .foregroundStyle(item.isAbnormal ? Color.red : .secondary)
                            } label: {
                                Text(item.isAbnormal ? "Value (abnormal)" : "Value")
                            }
                            LabeledContent("Reference Range", value: item.referenceRange ?? "Not recorded")
                            LabeledContent("Date", value: item.dateLabel)
                            LabeledContent("Source Facility", value: item.sourceName)
                            LabeledContent("Provenance") { ProvenanceBadge(provenance: item.provenance) }
                        }
                    }
                } else {
                    inspector
                }
            }
            .padding(.top, 8)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Record Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusPill(label: item.fhirVersion, icon: "chevron.left.forwardslash.chevron.right", tint: .indigo)
                Spacer()
                Button {
                    UIPasteboard.general.setItems(
                        [[UTType.plainText.identifier: item.rawJSON]],
                        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
                    )
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy JSON", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            ScrollView([.horizontal, .vertical]) {
                Text(verbatim: item.rawJSON)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.disabled)
                    .padding(14)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
