//
//  ShareComposeView.swift
//  ShareExtension
//
//  Created by anshu Li on 18/11/26.
//

import SwiftUI
import ImageIO

/// The share sheet's page: the shared text in an editable box, to check it before sending it to
/// Pipa. Same look as Pipa's "Adicionar com IA" page (grey background, white rounded box, ✕ on
/// the left and the blue ✓ on the right).
struct ShareComposeView: View {

    /// What happened after ✓.
    enum SendResult {
        /// Stored, and Pipa is opening.
        case openingApp
        /// Stored, but Pipa couldn't be opened from here: it shows the text next time.
        case savedForLater
        /// Not stored (the App Group isn't available).
        case failed
    }

    /// A shared photo or PDF, already copied into the App Group, with a small preview.
    struct SharedFile: Identifiable {
        let name: String
        let isPDF: Bool
        /// A small picture of the photo (or the PDF's first page); `nil` when it can't be made.
        let thumbnail: UIImage?
        /// Pages of a PDF.
        let pageCount: Int

        var id: String { name }

        init?(name: String) {
            guard let url = SharedInbox.fileURL(named: name) else { return nil }
            self.name = name
            isPDF = url.pathExtension.lowercased() == "pdf"
            if isPDF, let document = CGPDFDocument(url as CFURL) {
                pageCount = document.numberOfPages
                thumbnail = document.page(at: 1).flatMap { Self.render($0, maxSide: 240) }
            } else {
                pageCount = 1
                thumbnail = Self.thumbnail(of: url, maxSide: 240)
            }
        }

        /// A small copy of the photo, without decoding the full-size image (little memory here).
        private static func thumbnail(of url: URL, maxSide: CGFloat) -> UIImage? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSide
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        }

        private static func render(_ page: CGPDFPage, maxSide: CGFloat) -> UIImage? {
            let box = page.getBoxRect(.mediaBox)
            let longest = max(box.width, box.height)
            guard longest > 0 else { return nil }
            let scale = maxSide / longest
            let size = CGSize(width: box.width * scale, height: box.height * scale)
            return UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let cg = context.cgContext
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: scale, y: -scale)
                cg.drawPDFPage(page)
            }
        }
    }

    let initialText: String
    /// Photos and PDFs shared; when there are any, the page shows them instead of the text box.
    let files: [SharedFile]
    let onCancel: () -> Void
    let onSend: (String) -> SendResult

    @State private var text: String
    @State private var result: SendResult?
    @FocusState private var isFocused: Bool

    init(
        initialText: String,
        files: [SharedFile] = [],
        onCancel: @escaping () -> Void,
        onSend: @escaping (String) -> SendResult
    ) {
        self.initialText = initialText
        self.files = files
        self.onCancel = onCancel
        self.onSend = onSend
        self._text = State(initialValue: initialText)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result, result != .failed {
                    sent(result)
                } else if !files.isEmpty {
                    photos
                } else {
                    editor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("Adicionar ao Pipa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Cancelar"))
                }
                if result == nil || result == .failed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            isFocused = false
                            withAnimation(.snappy) { result = onSend(trimmed) }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12))
                                .bold()
                                .foregroundColor(.white)
                        }
                        .tint(.blue)
                        .buttonStyle(.glassProminent)
                        .disabled(trimmed.isEmpty && files.isEmpty)
                        .accessibilityLabel(Text("Enviar ao Pipa"))
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { isFocused = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Checking the text

    private var editor: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Confira o texto. No Pipa, ele vira itens de compra e tarefas para você revisar.")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.subtitle)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Ex.:\n2kg de arroz\ndetergente\nlavar a louça amanhã")
                            .foregroundStyle(.gray.opacity(0.6))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .accessibilityHidden(true)
                    }
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .foregroundStyle(Palette.title)
                        .accessibilityLabel(Text("Texto compartilhado"))
                }
                .font(.system(size: 17))
                .frame(minHeight: 220)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if result == .failed {
                    Text("Não foi possível enviar ao Pipa. Abra o app e tente de novo.")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Photos and PDFs

    private var photos: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Pipa, a IA lê a foto: os produtos de uma nota fiscal ou os ingredientes de uma receita.")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.subtitle)
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        Text("Recurso Premium")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.subtitle)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(files) { file in
                        preview(of: file)
                    }
                }

                if result == .failed {
                    Text("Não foi possível enviar ao Pipa. Abra o app e tente de novo.")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
            }
            .padding(22)
        }
    }

    private func preview(of file: SharedFile) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumbnail = file.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: file.isPDF ? "doc.richtext" : "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(Palette.subtitle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                }
            }
            .frame(height: 128)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if file.isPDF {
                Text(verbatim: "PDF · \(file.pageCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(file.isPDF ? Text(verbatim: "PDF") : Text("Foto"))
    }

    // MARK: - Sent

    private func sent(_ result: SendResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: result == .openingApp)
                .accessibilityHidden(true)

            Text("Enviado ao Pipa")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.title)

            Text(result == .openingApp
                 ? LocalizedStringKey("Abrindo o Pipa para você revisar…")
                 : LocalizedStringKey("Abra o Pipa para revisar os itens."))
                .font(.system(size: 15))
                .foregroundStyle(Palette.subtitle)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

/// Pipa's text colors (the extension doesn't have the app's asset catalog).
private enum Palette {
    /// `titleGray`.
    static let title = Color(.displayP3, red: 0.239, green: 0.239, blue: 0.239)
    /// `subTitleGray`.
    static let subtitle = Color(.displayP3, red: 0.541, green: 0.541, blue: 0.555)
}

#Preview {
    ShareComposeView(
        initialText: "Lista do mercado:\n- 2kg arroz\n- leite\n- lavar a louça amanhã",
        onCancel: {},
        onSend: { _ in .openingApp }
    )
}
