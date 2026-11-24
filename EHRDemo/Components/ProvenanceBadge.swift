import SwiftUI

struct ProvenanceBadge: View {
    let provenance: DataProvenance

    var body: some View {
        let isAppleHealth = provenance == .appleHealth
        StatusPill(
            label: provenance.label,
            icon: isAppleHealth ? "heart.fill" : "network",
            tint: isAppleHealth ? .pink : .blue
        )
    }
}

struct StatusPill: View {
    let label: String
    var icon: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.11), in: Capsule())
    }
}
