//
//  ChoresEmptyState.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 07/10/26.
//

import SwiftUI

/// What the chores screen shows when there is nothing to list.
///
/// Built from the app's own identity instead of a bare label: the piglet mascot over a
/// soft yellow disc with the `yellow.worms` texture, the same rounded cards and gray text
/// tones used by the onboarding, and one hint per floating button, so a user who just left the
/// onboarding learns what to do next.
struct ChoresEmptyState: View {
    
    /// The empty situations the chores screen can be in.
    enum Kind {
        /// The carousel ("Seu dia"): nothing is scheduled for today.
        case today
        /// The list ("Sua divisão"): the house has no chores to show.
        case division
        /// The list with a filter on that matches nothing.
        case filtered
    }
    
    /// Which empty case is shown.
    let kind: Kind
    
    /// When on, the mascot and sparkles don't move.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    /// Drives the mascot's gentle float and the sparkles' pulse.
    @State private var isAnimating = false
    
    // MARK: - Copy
    
    /// The headline of each case.
    private var title: LocalizedStringKey {
        switch kind {
        case .today: "Dia livre por aqui!"
        case .division: "Nada na sua divisão ainda"
        case .filtered: "Nenhuma tarefa encontrada"
        }
    }
    
    /// The explanation of each case.
    private var message: LocalizedStringKey {
        switch kind {
        case .today: "Você não tem tarefas para hoje. Aproveite o descanso ou adicione algo à sua rotina."
        case .division: "Quando as tarefas forem divididas, elas aparecem aqui."
        case .filtered: "Nenhuma tarefa corresponde ao filtro selecionado."
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 28) {
            // MARK: - Mascot
            mascot
            
            // MARK: - Title and message
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.titleGray)
                    .multilineTextAlignment(.center)
                
                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(.subTitleGray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Title and message read together.
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Mascot
    
    /// The piglet over a soft yellow disc, with two sparkles.
    private var mascot: some View {
        ZStack {
            Circle()
                .fill(RoomColor.blue.lowOpacityColor.opacity(0.3))
            
            SymbolImage(name: "kite")
                .foregroundStyle(RoomColor.blue.uiColor)
                .frame(width: 156, height: 156)
        }
        .frame(width: 176, height: 176)
        .clipShape(Circle())
        .overlay(alignment: .topTrailing) {
            sparkle(size: 24)
                .offset(x: 4, y: 6)
        }
        .overlay(alignment: .bottomLeading) {
            sparkle(size: 16)
                .offset(x: 2, y: -10)
        }
        .accessibilityHidden(true)
        .padding(.top, 30)
    }
    
    /// A sparkle that pulses gently.
    private func sparkle(size: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(RoomColor.blue.uiColor)
            .scaleEffect(isAnimating ? 1.15 : 0.85)
            .animation(
                .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                value: isAnimating
            )
    }
}

// MARK: - Hint row

/// One line pointing at a floating button, drawn like that button.
private struct ActionHint: View {
    /// SF Symbol of the button the hint points at.
    let systemImage: String
    /// The hint's text.
    let text: LocalizedStringKey
    
    /// `true` for the black "+" style, `false` for the light "hand" style.
    let isProminent: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            // MARK: Button-like icon
            ZStack {
                Circle()
                    .fill(isProminent ? Color.black : Color.white)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(isProminent ? 0 : 0.12), radius: 3, x: 0, y: 1)
                
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isProminent ? Color.white : Color.black)
            }
            
            // MARK: Hint text
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.titleGray)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(.systemGray6).opacity(0.5),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Seu dia") {
    ChoresEmptyState(kind: .today)
}

#Preview("Sua divisão") {
    ChoresEmptyState(kind: .division)
}

#Preview("Filtro") {
    ChoresEmptyState(kind: .filtered)
}
