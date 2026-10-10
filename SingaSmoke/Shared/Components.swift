import SingaSmokeCore
import SwiftUI

/// "Official" / "Indicative", plus "Approximate" when the pin is not exact. Icons, not colour alone.
struct ReliabilityChips: View {
    let reliability: Reliability
    var approximate = false

    var body: some View {
        HStack(spacing: 6) {
            Chip(text: reliability.label, symbol: reliability.symbol, tint: reliability.color)
            if approximate {
                Chip(text: "Approximate", symbol: "scope", tint: Brand.warning)
            }
        }
    }
}
