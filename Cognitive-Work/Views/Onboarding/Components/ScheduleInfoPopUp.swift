//
//  ScheduleInfoPopUp.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 28/09/26.
//

import SwiftUI

/// The pop-up shown over the first generated schedule, explaining how the division works:
/// it lasts 15 days, leftover chores can be picked up, and a retrospective comes at the end.
struct ScheduleInfoPopUp: View {
    /// Runs when the pop-up is closed.
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            // MARK: - Header: "EXPLICAÇÃO" and close button
            HStack {
                Text("EXPLICAÇÃO")
                    .font(.system(size: 13))
                    .bold()
                    .accessibilityLabel(Text(L10n.tr("Explicação")))
                
                Spacer()
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.black)
                        .fontWeight(.medium)
                        .padding(12)
                        .buttonStyle(.plain)
                        .glassEffect(
                            .regular.interactive(),
                            in: .capsule
                        )
                }
                .accessibilityLabel(Text(L10n.tr("Fechar")))
                .voiceControlNames([L10n.tr("Fechar"), L10n.tr("Cancelar")])
            }
            .padding(.top, 5)
            
            // MARK: - Title and intro
            Text("Sua escala está \npronta!")
                .font(.custom("Alan Sans", size: 32, relativeTo: .title))
                .bold()
                .foregroundStyle(.titleGray)
                .accessibilityAddTraits(.isHeader)
            
            Text("Dividimos as tarefas de acordo com o tempo livre de cada morador.")
                .font(.system(size: 16))
                .foregroundColor(.black.opacity(0.55))
            
            
            // MARK: - Three explanations: 15 days, chores to pick, retrospective
            VStack(alignment: .leading, spacing: 25) {
                HStack(spacing: 18) {
                    Image(systemName: "15.calendar")
                        .resizable()
                        .scaledToFit()
                        .frame(width: width * 0.1)
                        .foregroundColor(.choreOrange)
                        .accessibilityDecorative()
                    
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Vale por 15 dias")
                            .font(.system(size: 18))
                            .bold()
                        
                        Text("Depois desse período, tudo é redistribuído entre vocês.")
                            .font(.system(size: 15))
                    }
                }
                .accessibilityElement(children: .combine)
                
                HStack(spacing: 22) {
                    Image(systemName: "hand.tap")
                        .resizable()
                        .scaledToFit()
                        .frame(width: width * 0.08)
                        .foregroundColor(.choreYellow)
                        .accessibilityDecorative()
                    
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Tarefas à pegar")
                            .font(.system(size: 18))
                            .bold()
                        
                        Text("As tarefas que sobraram da divisão ficam na tela inicial, no botão \(Image(systemName: "hand.tap")). Pegue as que couberem no seu tempo.")
                            .font(.system(size: 15))
                    }
                    .frame(width: width * 0.6)
                }
                .accessibilityElement(children: .combine)
                
                HStack(spacing: 11) {
                    Image(systemName: "chart.bar.xaxis")
                        .resizable()
                        .scaledToFit()
                        .frame(width: width * 0.11)
                        .foregroundColor(.chorePurple)
                        .accessibilityDecorative()
                    
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Retrospectiva quinzenal")
                            .font(.system(size: 18))
                            .bold()
                        
                        Text("No fim dos 15 dias você terá uma analise completa de como foram suas atividades.")
                            .font(.system(size: 15))
                    }
                    .frame(width: width * 0.6)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.top, 15)
            
            // MARK: - "Ver minha escala" button
            Button {
                onDismiss()
            } label: {
                Text("Ver minha escala")
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular.interactive().tint(.blue),
                        in: .capsule
                    )
            }
            .voiceControlNames([L10n.tr("Ver minha escala"), L10n.tr("Ver escala"), L10n.tr("Escala")])
            .padding(.top, 15)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
        .frame(width: width * 0.87)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.2), radius: 3.2, x: 0, y: 4)
        )
        // A modal card: VoiceOver stays inside it, and the escape gesture closes it.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onDismiss() }
        .onAppear { VoiceOver.screenChanged() }
    }
}

#Preview {
    ScheduleInfoPopUp(onDismiss: {})
}
