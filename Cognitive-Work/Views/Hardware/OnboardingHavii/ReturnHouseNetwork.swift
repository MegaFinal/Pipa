//
//  ReturnHouseNetwork.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 28/10/26.
//

import SwiftUI

struct ReturnHouseNetwork: View {
    /// `true` for a moment after the password is copied.
    @State private var isPasswordCopied = false
    
    @Environment(\.openURL) private var openURL
    
    /// Side margin of the whole screen, the same as the onboarding steps.
    private var sideMargin: CGFloat { width * 0.0565 }
    
    var body: some View {
        NavigationStack{
            VStack(alignment: .center, spacing: 45) {
                
                OnboardingHeader(
                    title: "Volte para a rede da sua casa",
                    description: "Nos ajustes do celular, saia do Wi-Fi do Harvii e volte para a rede da sua casa, a mesma que você digitou no passo anterior.",
                    containerInset: sideMargin
                )
                .padding(.bottom)
                                
                WifiListExample(isHarviiNetwork: false)
                
                Spacer()
                
                openConfigurationButton
                
            }
            .padding(.horizontal, sideMargin)
            .padding(.bottom, height * 0.02)
            .overlay(alignment: .bottomTrailing) {
                OnboardingProgressButton(
                    width: width * 0.15,
                    height: width * 0.15,
                    text: "chevron.right",
                    isSystemImage: true
                ) {
                    // TODO: go to the next Harvii step.
                }
                .padding(.bottom, height * 0.02)
                .padding(.trailing, width * 0.061)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
    
    // MARK: openConfigurationButton
    
    /// "Abrir Ajustes" and the round "continue" button.
    private var openConfigurationButton: some View {
        
        Button {
            // iOS doesn't let apps open the Wi-Fi page directly; this opens Settings.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }label:{
            Text("Abrir ajustes")
                .frame(width: width * 0.45, height: height * 0.05)
            
            
        }
        .buttonStyle(.borderedProminent)
        .glassEffect()
        .tint(.black)
    }
}

#Preview {
    ReturnHouseNetwork()
}
