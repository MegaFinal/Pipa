//
//  PixKeySettingsView.swift
//  Cognitive-Work
//

import SwiftUI

/// Sheet where the user registers the Pix key housemates pay to when settling a debt.
struct PixKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: UserProfileViewModel
    /// Shows the "Chave Pix salva" toast.
    @State private var showSavedToast = false
    /// Shows the "Remover chave Pix?" confirmation.
    @State private var isConfirmingRemoval = false
    /// Whether the key field has the keyboard.
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack { content }
            .interactiveDismissDisabled(viewModel.isSaving)
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 26) {
            // MARK: - Title
            titleBlock

            // MARK: - Key field and caption
            VStack(alignment: .leading, spacing: 10) {
                Text("Sua chave")
                    .font(.system(size: 15))
                    .fontWeight(.semibold)

                keyField

                caption
            }

            // MARK: - Remove button (only when a key is saved)
            if viewModel.savedPixKey != nil {
                removeButton
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .navigationTitle("Chave Pix")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.startEditingPixKey() }
        .dismissKeyboardOnTap()
        .background(Color.groupedBackground.ignoresSafeArea())
        // MARK: - Save button
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) {
                    Task { await save() }
                }
                .disabled(!viewModel.canSavePixKey)
            }
        }
        // MARK: - Saved toast
        .overlay(alignment: .top) {
            if showSavedToast {
                Label("Chave Pix salva", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive().tint(.green), in: .capsule)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: showSavedToast)
        .animation(.snappy, value: viewModel.pixKeyError)
        // MARK: - Remove confirmation
        .confirmationDialog("Remover chave Pix?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remover", role: .destructive) {
                viewModel.editedPixKey = ""
                Task { await save() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Os moradores não vão conseguir te pagar pelo app até você cadastrar outra.")
        }
    }

    // MARK: - Pieces

    /// "Receba pelo Pix" and what the key is for.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receba pelo Pix")
                .bold()
                .font(.system(size: 32))

            Text("Os moradores usam essa chave para pagar o que devem a você em Pendências.")
                .font(.system(size: 16))
                .foregroundStyle(.subTitleGray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The key field, with a clear button and a red border on error.
    private var keyField: some View {
        Group {
            TextField(
                "",
                text: $viewModel.editedPixKey,
                prompt: Text("CPF, e-mail, celular ou chave aleatória").foregroundStyle(.gray)
            )
            .font(.system(size: 17))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .submitLabel(.done)
            .focused($isFieldFocused)
            .characterLimit(PixPayload.maxKeyLength, text: $viewModel.editedPixKey)
            .onChange(of: viewModel.editedPixKey) { _, _ in viewModel.pixKeyError = nil }

            if !viewModel.editedPixKey.isEmpty && isFieldFocused {
                Button {
                    viewModel.editedPixKey = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.subTitleGray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background (
            .white,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            if viewModel.pixKeyError != nil {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
            }
        }
        .disabled(viewModel.isSaving)
    }

    /// The error, or a tip about the phone format.
    @ViewBuilder
    private var caption: some View {
        if let error = viewModel.pixKeyError {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Para celular, use o formato +5511999999999.")
                .font(.system(size: 14))
                .foregroundStyle(.subTitleGray)
        }
    }

    /// "Remover chave".
    private var removeButton: some View {
        Button(role: .destructive) {
            isConfirmingRemoval = true
        } label: {
            Label("Remover chave", systemImage: "trash")
                .fontWeight(.semibold)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(viewModel.isSaving)
    }

    // MARK: - Actions

    /// Saves the key, shows the toast and closes the screen.
    private func save() async {
        isFieldFocused = false
        guard await viewModel.savePixKey() else { return }
        HapticsManager.selection()
        showSavedToast = true
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        showSavedToast = false
        dismiss()
    }
}

#Preview {
    let user = UserModel(name: "Preview User", tier: .tier1, ownerRecordName: "preview-owner")
    PixKeySettingsView(viewModel: UserProfileViewModel(user: user))
}
