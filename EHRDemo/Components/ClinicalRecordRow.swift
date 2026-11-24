import SwiftUI

struct ClinicalRecordRow: View {
    let item: ClinicalItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            let tint: Color = item.provenance == .appleHealth ? .pink : .blue
            Image(systemName: item.category.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if item.isAbnormal {
                    Label(item.subtitle, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.red)
                        .accessibilityLabel("Abnormal result, \(item.subtitle)")
                } else {
                    Text(item.subtitle).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { metadata }
                    VStack(alignment: .leading, spacing: 4) { metadata }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ProvenanceBadge(provenance: item.provenance)
                    .padding(.top, 2)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var metadata: some View {
        Label(item.dateLabel, systemImage: "calendar")
        Label(item.sourceName, systemImage: "building.2")
    }
}

extension ClinicalItem {
    var dateLabel: String {
        date == Self.unknownDate ? "Date unavailable" : date.formatted(date: .abbreviated, time: .omitted)
    }
}

private extension ClinicalCategory {
    var symbol: String {
        switch self {
        case .all: "list.bullet.rectangle"
        case .medications: "pills"
        case .labResults: "testtube.2"
        case .conditions: "stethoscope"
        case .allergies: "exclamationmark.shield"
        case .vitals: "waveform.path.ecg"
        case .immunizations: "syringe"
        }
    }
}
