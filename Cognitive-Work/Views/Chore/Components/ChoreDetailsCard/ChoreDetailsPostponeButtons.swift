//
//  ChoreDetailsPostponeButtons.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI

/// "Adiar 1 semana" and "Adiar 1 dia", side by side.
struct ChoreDetailsPostponeButtons: View {
    let viewModel: ChoreDetailsViewModel
    
    /// The labels in every language but Portuguese are shorter, so they need less horizontal padding.
    private var hasShortLabels: Bool { LanguageManager.shared.current != .portuguese }
    
    var body: some View {
        HStack {
            postponeButton("Adiar 1 semana", days: 7, horizontalPadding: hasShortLabels ? 18 : 25)
            Spacer()
            postponeButton("Adiar 1 dia", days: 1, horizontalPadding: hasShortLabels ? 18 : 32)
        }
        .frame(width: width * 0.72)
    }
    
    private func postponeButton(_ title: LocalizedStringKey, days: Int, horizontalPadding: CGFloat) -> some View {
        Button {
            Task { await viewModel.postpone(byDays: days) }
        } label: {
            // The text gives way to a spinner (keeping its size) while the date is saved.
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.black)
                .opacity(viewModel.postponingDays == days ? 0 : 1)
                .overlay {
                    if viewModel.postponingDays == days {
                        ProgressView().controlSize(.small)
                    }
                }
        }
        .disabled(viewModel.postponingDays != nil)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 10)
        .background(.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}
