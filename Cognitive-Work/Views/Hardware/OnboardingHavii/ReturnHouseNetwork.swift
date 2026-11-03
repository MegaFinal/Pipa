//
//  ReturnHouseNetwork.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 28/10/26.
//

import SwiftUI

struct ReturnHouseNetwork: View {
    /// The device connection's view model.
    @Bindable var viewModel: HardwareViewModel
    
    /// Closes the whole sheet, not just this step.
    var onClose: () -> Void
    
    /// `true` while pairing and sending the first chart; ``LoadingHarvii`` covers the screen.
    @State private var isConnecting = false
    
    @Environment(\.openURL) private var openURL
    
    /// Side margin of the whole screen, the same as the onboarding steps.
    private var sideMargin: CGFloat { width * 0.0565 }
    
    var body: some View {
        // No NavigationStack here: this step is pushed inside WelcomeHarviiView's stack.
        Group {
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
                    await connect()
                }
                .padding(.bottom, height * 0.02)
                .padding(.trailing, width * 0.061)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            
            // MARK: - Loading while the Harvii pairs and gets the chores
            .overlay {
                if isConnecting {
                    LoadingHarvii()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.onboardingBackground).ignoresSafeArea())
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: isConnecting)
            // No going back while the Harvii is still answering.
            .navigationBarBackButtonHidden(isConnecting)
            
            // MARK: - Result
            .navigationDestination(isPresented: $viewModel.navigateToConnectionHarviiView) {
                ConnectionHarvii(
                    didConnectionSucced: viewModel.conectionResult == .success,
                    errorDetail: viewModel.pairingErrorDetail,
                    onClose: onClose
                )
            }
        }
    }
    
    // MARK: - Actions
    
    /// Behind ``LoadingHarvii``: pairs with the Harvii, then sends it the chores image and waits
    /// for its answer (and for the e-paper to show it). Then opens ``ConnectionHarvii`` with the
    /// result: success only when the image got there.
    private func connect() async {
        isConnecting = true
        VoiceOver.announce(L10n.tr("Pareando com o Harvii…"))
        await viewModel.pair(sendingChart: false)
        if viewModel.conectionResult == .success {
            await viewModel.sendFirstChart()
        }
        isConnecting = false
        viewModel.navigateToConnectionHarviiView = true
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
    NavigationStack {
        ReturnHouseNetwork(viewModel: HardwareViewModel(), onClose: {})
    }
}
