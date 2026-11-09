//
//  ConnectionHarvii.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 28/10/26.
//

import SwiftUI

/// Last step of the Harvii setup: shows whether the phone paired with the Harvii.
struct ConnectionHarvii: View {
    /// Whether the panel is up (it slides in when the screen appears).
    @State var showSheet: Bool = false
    
    /// Whether the phone paired with the Harvii (`true`) or it failed (`false`).
    let didConnectionSucced: Bool
    
    /// Why it failed, shown in the orange box; `nil` hides the box.
    var errorDetail: String? = nil
    
    /// Closes the whole sheet.
    var onClose: () -> Void
    
    /// The error box text: the app's orange, darkened to keep 4.5:1 contrast on the light box.
    private static let errorTextColor = Color(red: 173 / 255, green: 70 / 255, blue: 46 / 255)
    
    var body: some View {
        ZStack {
            heroImage
            
            if showSheet {
                resultPanel
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1)) {
                showSheet = true
            }
        }
        // The X closes the setup. On failure, "back" also stays, to try pairing again.
        .navigationBarBackButtonHidden(didConnectionSucced)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .voiceOverLabel(L10n.tr("Fechar"))
                .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
            }
        }
        .background {
            (didConnectionSucced ? Color.lowOpacityGreen : Color.lowOpacityOrange)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Subviews

private extension ConnectionHarvii {
    
    /// Harvii picture at the top, with the check badge on its corner when it connected.
    var heroImage: some View {
        Image("onboardingHarvii")
            .resizable()
            .scaledToFit()
            // Before the frame: the badge sits on the picture's corner, not on the screen's.
            .overlay(alignment: .topTrailing) {
                resultBadge
                    .offset(x: -width * 0.02, y: height * 0.07)
            }
            .frame(width: width, height: height - 100, alignment: .top)
            .offset(y: height * 0.04)
            .shadow(radius: 4.0)
    }
    
    /// Round badge on the Harvii's corner: green check when it connected, orange X when it failed.
    var resultBadge: some View {
        let color = didConnectionSucced ? Color.choreGreen : Color.choreOrange
        return Image(systemName: didConnectionSucced ? "checkmark" : "xmark")
            .font(.system(size: 28).weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: width * 0.16, height: width * 0.16)
            .background(color, in: .circle)
            .glassEffect(.regular.tint(color), in: .circle)
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            // The title already says how it went.
            .accessibilityDecorative()
    }
    
    /// Orange box with the specific reason it failed.
    func errorBox(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.choreOrange)
                .accessibilityDecorative()
            
            Text(detail)
                .foregroundStyle(Self.errorTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 17))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.choreOrange.opacity(0.12), in: .rect(cornerRadius: 20))
        // VoiceOver reads it after the description, as one element.
        .accessibilityElement(children: .combine)
        .padding(.top, height * 0.028)
    }
    
    /// White panel with the result texts.
    var resultPanel: some View {
        resultTexts
            .padding(.horizontal, height * 0.028)
            .padding(.bottom, height * 0.15)
            .frame(width: width)
            .frame(minHeight: height * 0.55, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.white)
            .clipShape(
                UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
            )
    }
    
    /// Title and description of the result.
    var resultTexts: some View {
        VStack(alignment: .leading) {
            if didConnectionSucced {
                Text("Harvii está conectado!")
                    .font(.custom("Alan Sans", fixedSize: 32))
                    .bold()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, height * 0.052)
                    .padding(.bottom, height * 0.028)
                
                Text("Quando alguém completar alguma tarefa no celular, o Harvii atualizará sozinho.\nPosicione seu Harvii em um local que todos os moradores passem, como a cozinha, a sala ou o corredor.")
                    .font(.system(size: 17))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Não foi possível conectar o Harvii")
                    .font(.custom("Alan Sans", fixedSize: 32))
                    .bold()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, height * 0.052)
                    .padding(.bottom, height * 0.028)
                
                Text("Confira se o celular está no mesmo Wi-Fi que você enviou para o Harvii e tente de novo.")
                    .font(.system(size: 17))
                    .fixedSize(horizontal: false, vertical: true)
                
                if let errorDetail {
                    errorBox(errorDetail)
                }
            }
            
            Spacer()
        }
    }
}

#Preview("Sucesso") {
    NavigationStack { ConnectionHarvii(didConnectionSucced: true, onClose: {}) }
}

#Preview("Falha") {
    NavigationStack {
        ConnectionHarvii(
            didConnectionSucced: false,
            errorDetail: HardwareViewModel.pairingErrorMessage(for: URLError(.timedOut)),
            onClose: {}
        )
    }
}
