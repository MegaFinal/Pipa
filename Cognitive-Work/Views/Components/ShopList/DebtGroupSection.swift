//
//  DebtGroupSection.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 08/10/26.
//

import SwiftUI

/// What one housemate owes (or is owed) in the "Pendências" screen, drawn as a receipt
struct DebtGroupSection: View {

    let user: UserModel?
    let title: String
    var banner: ProfileBanner = .default
    let totalText: String
    let rows: [Row]
    let settleTitle: String
    var settleSystemImage: String? = nil
    let isPaid: Bool
    let isSettling: Bool
    let onSettle: () -> Void

    var isConfirmingSettlement: Bool = false
    var confirmationTitle: String = ""
    var confirmationMessage: String = ""
    var confirmationButtonTitle: String = ""
    var onConfirmSettlement: () -> Void = {}
    var onCancelSettlement: () -> Void = {}

    var headerAccessibilityText: String? = nil
    var totalAccessibilityText: String? = nil
    var settleAccessibilityLabel: String? = nil
    var settleAccessibilityValue: String = ""

    /// One item line of the receipt.
    struct Row: Identifiable {
        let id: String
        let name: String
        let amountText: String
        var accessibilityAmount: String? = nil
    }

    /// The radius of the two half-circle bites on the receipt's sides.
    private let notchRadius: CGFloat = 10

    /// Where the bites go: lined up with the tear line, measured from the receipt's top.
    @State private var tearY: CGFloat = -1_000

    /// Name of the coordinate space the tear line is measured in.
    private let receiptSpace = "receipt"

    private var paper: some View {
        ZStack {
            Color.white
            Color.choreYellow.opacity(0.12)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Banner: avatar, name and settle button
            bannerView

            VStack(alignment: .leading, spacing: 18) {
                // MARK: - Items
                itemRows

                // MARK: - Tear line, with a bite on each side of the receipt
                tearLine
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .named(receiptSpace)).midY
                    } action: { tearY = $0 }

                // MARK: - Total
                totalRow
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .coordinateSpace(name: receiptSpace)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paper)
        .clipShape(ReceiptShape(notchRadius: notchRadius, notchY: tearY, tornBottom: true))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Pieces

    /// The colored banner: avatar, name, how many items and the settle button.
    private var bannerView: some View {
        HStack(spacing: 12) {
            UserProfilePictureTag(user: user, widthMultiplier: 0.1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Alan Sans", size: 22))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .voiceOverLabel(headerAccessibilityText ?? "\(title), \(L10n.tr("Total")) \(totalText)")
                    .accessibilityAddTraits(.isHeader)

                Text(rows.count == 1 ? L10n.tr("1 item") : L10n.tr("\(rows.count) itens"))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .opacity(0.85)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 8)

            settleButton
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .background {
            RoomTextureBackground(color: banner.color, pattern: banner.pattern, zoom: 1.5)
        }
    }

    /// The dotted tear line.
    private var tearLine: some View {
        Line()
            .stroke(banner.color.uiColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 7]))
            .frame(height: 1.5)
            .accessibilityHidden(true)
    }

    /// One line per item, typed like a receipt
    private var itemRows: some View {
        VStack(spacing: 12) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 16, design: .monospaced))
                        .lineLimit(2)

                    Line()
                        .stroke(Color.gray.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5]))
                        .frame(minWidth: 12, maxHeight: 2)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }

                    Text(row.amountText)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.titleGray)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(row.name), \(row.accessibilityAmount ?? row.amountText)"))
            }
        }
    }

    /// "TOTAL" and the amount, bigger than the items.
    private var totalRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.tr("Total").uppercased())
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .tracking(2)

            Spacer(minLength: 12)

            Text(totalText)
                .font(.custom("Alan Sans", size: 30))
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.black)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(L10n.tr("Total")), \(totalAccessibilityText ?? totalText)"))
    }

    /// "Pagar" or "Recebi" until it's tapped, then "Pago!". It is always a black capsule. When you owe, `onSettle` copies the
    /// Pix "copia e cola".
    private var settleButton: some View {
        Button(action: onSettle) {
            settleLabel
        }
        .buttonStyle(.plain)
        .disabled(isPaid || isSettling)
        .opacity(isSettling && !isPaid ? 0.5 : 1)
        .animation(.snappy, value: isPaid)
        .popover(
            isPresented: Binding(
                get: { isConfirmingSettlement },
                set: { if !$0 { onCancelSettlement() } }
            ),
            attachmentAnchor: .point(.bottom),
            arrowEdge: .top
        ) {
            confirmationPopover
                .presentationCompactAdaptation(.popover)
        }
        .voiceOverLabel(settleAccessibilityLabel ?? settleTitle)
        .voiceOverValue(settleAccessibilityValue)
        .voiceControlNames(settleInputLabels)
    }

    /// What comes out of the button: the question, the warning and the two choices.
    private var confirmationPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(confirmationTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)

            Text(confirmationMessage)
                .font(.system(size: 15))
                .foregroundStyle(.subTitleGray)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(role: .cancel, action: onCancelSettlement) {
                    Text("Cancelar")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.08)))
                }

                Button(action: onConfirmSettlement) {
                    Text(confirmationButtonTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 300)
    }

    /// Speakable names for the settle button: what it shows, then one naming the person.
    private var settleInputLabels: [String] {
        isPaid ? [settleTitle] : [settleTitle, L10n.tr("Pagar \(title)")]
    }

    /// The settle button's look: a black capsule with a short title on one line, and a checkmark
    /// once paid.
    private var settleLabel: some View {
        HStack(spacing: 6) {
            if isPaid {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
            } else if let settleSystemImage {
                Image(systemName: settleSystemImage)
                    .font(.system(size: 13, weight: .bold))
            }
            Text(settleTitle)
                .lineLimit(1)
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .fixedSize()
        .background(Capsule().fill(Color.black))
    }

    /// A straight horizontal line across the middle of its frame.
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

#Preview("Seção") {
    DebtGroupSection(
        user: ShopListPreviewData.isabela,
        title: "Isabela",
        banner: ProfileBanner(color: .purple, pattern: .stars),
        totalText: "R$45,00",
        rows: [
            .init(id: "1", name: "Pizza", amountText: "R$30,00"),
            .init(id: "2", name: "Sabão em pó", amountText: "R$21,00")
        ],
        settleTitle: "Pagar",
        isPaid: false,
        isSettling: false,
        onSettle: {}
    )
    .padding()
}
