import SingaSmokeCore
import SwiftUI

/// Kinds of shop as toggles: filled when shown, outlined when hidden. At least one stays on.
struct CategoryChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RetailCategory.allCases) { category in
                    let on = model.retailerCategories.contains(category)
                    Button {
                        if on {
                            if model.retailerCategories.count > 1 { model.retailerCategories.remove(category) }
                        } else {
                            model.retailerCategories.insert(category)
                        }
                    } label: {
                        Label(category.label, systemImage: category.symbol)
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundStyle(on ? Color.white : category.color)
                            .background(on ? category.color : Brand.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(category.color.opacity(on ? 0 : 0.5), lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityHint(on ? "Hides this kind of shop" : "Shows this kind of shop")
                }
            }
            .padding(.vertical, 12)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .fixedSize(horizontal: false, vertical: true)   // only as tall as the chips: the map stays draggable
        .padding(.horizontal, -16)
        .padding(.vertical, -12)
        .sensoryFeedback(.selection, trigger: model.retailerCategories)
    }
}
