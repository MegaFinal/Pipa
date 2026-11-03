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
        HStack {
            // MARK: - Icon
            ZStack {
                Capsule()
                    .foregroundStyle(color)
                    .frame(width: width * 0.12, height: height * 0.065)
                Image(systemName: symbol)
                    .font(.system(size: 20))
            }.padding(.trailing, 16)
            // The icon only repeats the notification's kind, which the title already says.
            .accessibilityDecorative()
            
            // MARK: - Title and subtitle
            VStack(alignment: .leading, spacing: 8){
                Text(title)
                    .font(.system(size: 20))
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.subTitleGray)
                    
            }
            .frame(width: width * 0.62, alignment: .leading)
        }
        // "3 tarefas a pegar hoje, Escolha as que couberem no seu tempo" as one element.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NotificationComponent(color: .lowOpacityBlue, symbol: "hand.tap", title: "3 tarefas a pegar hoje", subtitle: "Escolha as que couberem no seu tempo")
}
