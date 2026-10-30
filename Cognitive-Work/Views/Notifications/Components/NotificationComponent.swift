//
//  NotificationComponent.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 30/09/26.
//

import SwiftUI

/// One row of the notifications screen: a colored icon and two lines of text.
struct NotificationComponent: View {
    /// The icon's background color.
    let color: Color
    /// SF Symbol of the icon.
    let symbol: String
    /// The first line.
    let title: String
    /// The second line.
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            // MARK: - Icon
            ZStack {
                Capsule()
                    .fill(color)
                    .opacity(0.45)
                    .frame(width: 48, height: 60)
                Image(systemName: symbol)
                    .font(.system(size: 22))
            }
            // The icon only repeats the notification's kind, which the title already says.
            .accessibilityDecorative()
            
            // MARK: - Title and subtitle
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.leading)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(.subTitleGray)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The whole row is tappable, not just the icon and the text.
        .contentShape(Rectangle())
        // "3 tarefas a pegar hoje, Escolha as que couberem no seu tempo" as one element.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NotificationComponent(color: .lowOpacityBlue, symbol: "hand.tap", title: "3 tarefas a pegar hoje", subtitle: "Escolha as que couberem no seu tempo")
}
