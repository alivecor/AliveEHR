import SwiftUI

struct CategoryFilterBar: View {
    @Binding var selection: ClinicalCategory
    let tint: Color

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ClinicalCategory.allCases) { category in
                    Button {
                        selection = category
                    } label: {
                        Text(category.rawValue)
                            .font(.subheadline.weight(selection == category ? .semibold : .regular))
                            .foregroundStyle(selection == category ? tint : Color.primary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(
                                selection == category ? tint.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().strokeBorder(selection == category ? tint.opacity(0.32) : Color.secondary.opacity(0.15))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == category ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Clinical categories")
    }
}
