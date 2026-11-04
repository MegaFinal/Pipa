//
//  ShareHouseButton.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 25/08/26.
//

import SwiftUI
import CloudKit

/// The "Compartilhar Convite" button: creates the house's invite link and opens the share sheet.
struct ShareHouseButton: View {
    /// The onboarding's view model.
    let viewModel: OnboardingViewModel

    /// The button's width; the default is half the screen.
    var width: CGFloat?
    /// The button's height; the default is 6% of the screen.
    var height: CGFloat?

    /// The house's share. The button stays gray until it exists.
    @Binding var share: CKShare?
    /// The invite link, set when it is created.
    @Binding var shareURL: URL?
    /// Opens the share sheet once the link is ready.
    @Binding var showSheet: Bool

    /// `true` while the link is being created.
    @State private var isLoading = false

    // `width`/`height` shadow the View extension's properties of the same
    // name, so casting to `any View` is needed to reach the extension's
    // default (screen-based) value when no override was passed in.
    /// ``width`` or the default.
    private var resolvedWidth: CGFloat { width ?? (self as any View).width * 0.5 }
    /// ``height`` or the default.
    private var resolvedHeight: CGFloat { height ?? (self as any View).height * 0.06 }

    var body: some View {
        
        // MARK: - Creates the link, then opens the share sheet
        Button {
            Task {
                guard let share = share else { return }
                isLoading = true

                do {
                    let url = try await CloudKitManager.shared.generateShareLink(share: share)
                    self.shareURL = url
                    self.showSheet = true
                } catch {
                    print("Erro ao gerar link: \(error.localizedDescription)")
                    VoiceOver.announce(L10n.tr("Não foi possível gerar o link do convite"))
                }
                
                isLoading = false
            }
        } label: {
            // MARK: - Label: spinner or text, in a blue (or gray) capsule
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Compartilhar Convite")
                        .font(.system(size: 17))
                }
            }
            .frame(width: resolvedWidth, height: resolvedHeight)
            .foregroundColor(.white)
            .background(Capsule().foregroundColor(share == nil || isLoading ? .gray : .blue))
        }
        .disabled(share == nil || isLoading)
        .accessibilityLabel(Text(L10n.tr("Compartilhar Convite")))
        .voiceControlNames([L10n.tr("Compartilhar Convite"), L10n.tr("Compartilhar"), L10n.tr("Convidar")])
        .voiceOverValue(isLoading ? L10n.tr("Gerando link") : "")
        .voiceOverHint(share == nil ? L10n.tr("Aguarde, o convite ainda está sendo preparado") : L10n.tr("Abre as opções para enviar o link da casa"))
    }
}


#Preview("Convite pronto") {
    @Previewable @State var share: CKShare? = CKShare(
        rootRecord: CKRecord(recordType: HouseModel.recordType)
    )
    @Previewable @State var shareURL: URL? = nil
    @Previewable @State var showSheet = false

    ShareHouseButton(
        viewModel: OnboardingViewModel(),
        share: $share,
        shareURL: $shareURL,
        showSheet: $showSheet
    )
}

#Preview("Sem convite") {
    @Previewable @State var share: CKShare? = nil
    @Previewable @State var shareURL: URL? = nil
    @Previewable @State var showSheet = false

    ShareHouseButton(
        viewModel: OnboardingViewModel(),
        share: $share,
        shareURL: $shareURL,
        showSheet: $showSheet
    )
}
