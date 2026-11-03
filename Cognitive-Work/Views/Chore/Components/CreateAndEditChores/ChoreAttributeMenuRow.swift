//
//  ChoreAttributeMenuRow.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 22/10/26.
//

import SwiftUI

/// A form row: the attribute's name on the left and, on the right, a menu showing the current
/// value as a colored dot, the value in gray and up/down chevrons
struct ChoreAttributeMenuRow<Options: View>: View {
    let title: LocalizedStringKey
    let value: String
    let color: Color
    var isSuggested = false
    @ViewBuilder let options: () -> Options
    
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Text(title)
                    .fontWeight(.semibold)

                if isSuggested {
                    Image(systemName: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: isSuggested)
            .accessibilityHidden(true)
            
            Spacer(minLength: 12)
            
            Menu {
                options()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                    
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            // A menu draws its label in the accent color (blue) by default, which would
            // override the gray of the value and the chevrons.
            .tint(.secondary)
            .accessibilityLabel(Text(title))
            .accessibilityValue(isSuggested ? value + ", " + L10n.tr("Sugerido automaticamente") : value)
        }
    }
}

struct ChoreMenuOption: View {
    let title: String
    let color: Color
    
    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(uiImage: .coloredCircle(color: color))
                .renderingMode(.original)
        }
    }
}
