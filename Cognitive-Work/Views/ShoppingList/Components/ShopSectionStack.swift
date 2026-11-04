//
//  ShopSectionStack.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI

/// The shopping list's cards, stacked like folders.
struct ShopSectionStack<Row: View>: View {
    var viewModel: ShopListViewModel
    let sections: [ShopListSection]
    let row: (ShopListItem) -> Row
    /// Extra content at the end of an open card, after its items (the AI suggestions of that category); `nil` adds nothing.
    let footer: ((ShopListSection) -> AnyView)?

    /// How much a closed card hides under the next one
    private let overlap: CGFloat = 24
    /// Space between a card and the one below it
    private let gap: CGFloat = 16
    /// The animation of a card opening or closing.
    static var moveAnimation: Animation { .spring(response: 0.5, dampingFraction: 0.86) }

    init(
        viewModel: ShopListViewModel,
        sections: [ShopListSection],
        footer: ((ShopListSection) -> AnyView)? = nil,
        @ViewBuilder row: @escaping (ShopListItem) -> Row
    ) {
        self.viewModel = viewModel
        self.sections = sections
        self.footer = footer
        self.row = row
    }

    var body: some View {
        let entries = viewModel.stackEntries(for: sections)

        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ShopSectionCard(
                    section: entry.section,
                    isExpanded: entry.isExpanded,
                    joinsAbove: entry.followsExpanded,
                    accessibilityLabel: viewModel.accessibilityLabel(for: entry.section),
                    accessibilityValue: viewModel.accessibilityValue(for: entry.section),
                    onToggle: {
                        HapticsManager.selection()
                        withAnimation(Self.moveAnimation) {
                            viewModel.toggleCollapsed(entry.section)
                        }
                    },
                    footer: footer,
                    row: row
                )
                .padding(.bottom, entry.overlapsNext ? -overlap : (entry.precedesExpanded ? 0 : gap))
                .zIndex(entry.id == viewModel.movingSectionID ? 1_000 : Double(index))
            }
        }
    }
}

// MARK: - Card

/// One card of the stack
struct ShopSectionCard<Row: View>: View {
    let section: ShopListSection
    let isExpanded: Bool
    let joinsAbove: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let onToggle: () -> Void
    /// See ``ShopSectionStack/footer``.
    var footer: ((ShopListSection) -> AnyView)? = nil
    let row: (ShopListItem) -> Row

    private var color: Color { section.category?.color ?? .titleGray }
    private let cornerRadius: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                items
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .overlay(alignment: .top) {
            if joinsAbove {
                ShopCardStitching(color: color, inset: cornerRadius)
                    .offset(y: -ShopCardStitching.height)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                if let category = section.category {
                    SymbolImage(name: category.symbol)
                        .frame(width: 52, height: 52)
                }

                Text(section.title)
                    .font(.custom("Alan Sans", size: 22))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(section.items.count)")
                    .font(.system(size: 17))

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .foregroundStyle(.white)
            .padding(.leading, section.category == nil ? 20 : 8)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 78)
            .background(color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .voiceOverLabel(accessibilityLabel)
        .voiceOverValue(accessibilityValue)
        .voiceControlNames([section.title])
        .accessibilityAddTraits(.isHeader)
    }

    /// The section's items, separated by thin lines.
    private var items: some View {
        VStack(spacing: 0) {
            ForEach(section.items) { item in
                row(item)

                if item.id != section.items.last?.id {
                    ShopDottedDivider()
                        .padding(.vertical, 12)
                }
            }

            // After the items: the AI suggestions of this category, if any.
            if let footer {
                footer(section)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Divider

/// The dotted line between two items (also above a category's AI suggestions).
struct ShopDottedDivider: View {

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 1, y: 1))
                path.addLine(to: CGPoint(x: proxy.size.width - 1, y: 1))
            }
            .stroke(Color.gray.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 6]))
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Stitching

/// The stitches that sew an open card onto the one above it.
private struct ShopCardStitching: View {
    let color: Color
    let inset: CGFloat
    static let height: CGFloat = 8
    @State private var sewn: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: Self.height / 2))
                path.addLine(to: CGPoint(x: proxy.size.width, y: Self.height / 2))
            }
            .trim(from: 0, to: sewn)
            .stroke(color, style: StrokeStyle(lineWidth: Self.height, dash: [6, 6]))
        }
        .frame(height: Self.height)
        .padding(.horizontal, inset)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                sewn = 1
            }
        }
    }
}

// MARK: - Previews

#Preview("Pilha de cards") {
    ScrollView {
        ShopListStackPreview()
            .padding(.horizontal, 20)
    }
}

/// Preview host that keeps its own view model.
private struct ShopListStackPreview: View {
    @State private var viewModel = ShopListPreviewData.populatedViewModel

    var body: some View {
        ShopSectionStack(viewModel: viewModel, sections: viewModel.pendingSections) { item in
            ShopListItemCard(
                item: item,
                relatedUsers: viewModel.relatedUsers(for: item),
                onToggle: {},
                onTap: {}
            )
        }
    }
}
