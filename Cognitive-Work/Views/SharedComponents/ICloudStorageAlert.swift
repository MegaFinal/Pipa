//
//  ICloudStorageAlert.swift
//  Cognitive-Work
//
//  Created by Jonas Melo on 11/11/26.
//

import SwiftUI

extension View {

    /// Shows an alert, from any screen, when CloudKit stops saving because an iCloud account is
    /// full. See ``ICloudStorageMonitor``.
    func iCloudStorageAlert() -> some View {
        modifier(ICloudStorageAlert())
    }
}

/// The full-iCloud alert. See ``SwiftUI/View/iCloudStorageAlert()``.
private struct ICloudStorageAlert: ViewModifier {

    /// Where full-iCloud errors are reported.
    private var monitor = ICloudStorageMonitor.shared

    /// Opens the Settings app.
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .alert(
                L10n.tr("iCloud cheio"),
                isPresented: Binding(
                    get: { monitor.notice != nil },
                    set: { if !$0 { monitor.dismiss() } }
                ),
                presenting: monitor.notice
            ) { notice in
                // Only the current user can free their own space; the house owner's is out of reach.
                if notice.owner != .houseOwner {
                    Button(L10n.tr("Abrir Ajustes")) {
                        monitor.dismiss()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                Button(L10n.tr("Agora não"), role: .cancel) {
                    monitor.dismiss()
                }
            } message: { notice in
                Text(message(for: notice))
            }
    }

    /// The explanation for `notice`, depending on whose iCloud is full.
    private func message(for notice: ICloudStorageMonitor.Notice) -> String {
        switch notice.owner {
        case .currentUser:
            return L10n.tr("Seu iCloud está sem espaço, então suas alterações não estão sendo salvas. Libere espaço no iCloud para continuar.")
        case .houseOwner:
            return L10n.tr("O iCloud de quem criou a casa está sem espaço, então as alterações da casa não estão sendo salvas. Peça para essa pessoa liberar espaço no iCloud.")
        case nil:
            return L10n.tr("O armazenamento do iCloud está cheio, então algumas alterações não foram salvas. Libere espaço no iCloud para continuar.")
        }
    }
}
