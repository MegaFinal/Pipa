//
//  WifiListExample.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 28/10/26.
//

import SwiftUI

/// A mock of Settings > Wi-Fi that shows which network the phone should be on during the
/// Harvii setup: the Harvii's own network or the home Wi-Fi. The one to pick gets a blue border.
///
/// ```swift
/// WifiListExample(isHarviiSelected: true)   // "join the Harvii network"
/// WifiListExample(isHarviiSelected: false)  // "go back to your Wi-Fi"
/// ```
struct WifiListExample: View {

    /// `true` highlights the Harvii network; `false` highlights the home network.
    var isHarviiNetwork: Bool

    /// Name of the network the Harvii creates, as the phone lists it.
    var harviiNetworkName = "ESP32"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ajustes > Wi-Fi")
                .font(.caption.weight(.semibold))

            WifiRow(
                name: Text(verbatim: harviiNetworkName),
                caption: "rede do Harvii",
                isSelected: isHarviiNetwork
            )

            WifiRow(
                name: Text("Sua rede"),
                caption: "rede da sua casa",
                isSelected: !isHarviiNetwork
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .animation(.snappy, value: isHarviiNetwork)
    }
}

/// One network of the list. The selected one is white with a blue border; the other is gray.
private struct WifiRow: View {
    /// The network's name.
    let name: Text
    /// Small text on the right, e.g. "Rede do Harvii".
    var caption: LocalizedStringKey? = nil
    /// Whether this is the network to pick.
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: "wifi")

            name
                .font(isSelected ? .headline : .body)

            Spacer()

            if isSelected, let caption {
                Text(caption)
                    .font(.subheadline)
            }
        }
        .foregroundStyle(isSelected ? .primary : .secondary)
        .padding()
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white)
                    .stroke(.blue, lineWidth: 3)
            }
        }
    }
}

#Preview("Rede do Harvii") {
    WifiListExample(isHarviiNetwork: true)
        .padding()
}

#Preview("Rede da casa") {
    WifiListExample(isHarviiNetwork: false)
        .padding()
}
