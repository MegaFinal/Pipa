//
//  PairedView.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 28/10/26.
//

import SwiftUI

struct PairedView: View {
    /// The device connection's view model.
    @Bindable var hardwareViewModel: HardwareViewModel
    /// Shows the "Celular desconectado" alert.
    @State private var disconectThisPhone = false
    /// Closes the whole sheet, not just this step.
    var onClose: () -> Void
    
    var body: some View {
        
        let wifiName = (hardwareViewModel.wifiName == "") ? L10n.tr("Sem WiFi armazenado") : hardwareViewModel.wifiName
        
        VStack(alignment: .leading) {
            Text("Seu Harvii está\n\(Text("pareado").foregroundStyle(.choreGreen))!")
                .font(.custom("Alan Sans", size: 32, relativeTo: .largeTitle))
                .bold()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, height * 0.014)
            
            Text("Harvii está recebendo as atualizações das tarefas da sua casa em tempo real!\nQuando alguém completar alguma tarefa no celular, o Harvii atualizará sozinho.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Nome da sua rede")
                    .font(.subheadline.weight(.semibold))
                
                Text(wifiName)
                    .font(.body)
                    .foregroundStyle(.subTitleGray)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGroupedBackground), in: .rect(cornerRadius: 20))
            }
            .padding(.top, height * 0.02)
            .accessibilityElement(children: .combine)
            
            Spacer()
            
            Button {
                hardwareViewModel.disconnectThisPhone()
                disconectThisPhone = true
            } label: {
                Text("Desparear")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray5), in: .capsule)
            }
            .voiceControlNames([L10n.tr("Desparear este celular"), L10n.tr("Desparear")])
            .buttonStyle(.plain)
            .padding(.bottom, height * 0.14)
        }
        .padding(.horizontal, height * 0.028)
        
        // MARK: - Disconnected alert
        .alert("Celular desconectado.", isPresented: $disconectThisPhone) {
            Button("OK") { onClose() }
        } message: {
            Text("Seu celular foi desconectado com sucesso!")
        }
    }
}

#Preview {
    var vm = HardwareViewModel()
    vm.wifiName = "Rede maneira"
    return PairedView(hardwareViewModel: vm, onClose: {})
}
