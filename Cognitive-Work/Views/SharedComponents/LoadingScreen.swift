//
//  LoadingScreen.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI

/// Full-screen loading state: a spinning icon and a message over a soft texture.
struct LoadingScreen: View {
    /// The message under the icon.
    var title: LocalizedStringKey = "Carregando sua casa..."
    
    /// The icon's angle; animated forever while on screen.
    @State private var rotation = 0.0
    
    var body: some View {
        VStack(spacing: 24) {
            // MARK: - Spinning icon
            Image("loadingIcon")
                .rotationEffect(.degrees(rotation))
                .accessibilityDecorative()
                .onAppear {
                    withAnimation(.linear(duration: 1).speed(0.3).repeatForever(autoreverses: false)) {
                        rotation = 360.0
                    }
                }
            
            // MARK: - Message
            Text(title)
                .font(.system(size: 28))
                .bold()
            
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // MARK: - Background texture
        .background(
            Image("yellow.sparkles")
                .resizable()
                .opacity(0.2)
                .frame(width: width * 1.6)
                .ignoresSafeArea()
                .accessibilityDecorative()
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    LoadingScreen()
}
