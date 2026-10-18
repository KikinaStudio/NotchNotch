import SwiftUI

/// The composer's `/` palette (`SlashPalette`): one row per suggestion, name then description on
/// the same line (as Hermes Desktop), the typed part in bold, under COMMANDES / SKILLS / HERMES.
/// It sits between the conversation and the field: the conversation shrinks, the panel keeps its
/// size. A fill one step lighter than the panel sets it apart (Jérémie found the bare list as dark
/// as the notch); hairlines between rows, a tint and the accent dot on the selected one.
/// `ChatView` owns the selection and the keys (↑ ↓ Tab Enter Esc).
struct SlashPaletteView: View {
    let query: String
    let items: [SlashSuggestion]
    let selectedIndex: Int?
    let onHover: (Int) -> Void
    let onPick: (SlashSuggestion) -> Void

    private static let maxHeight = CGFloat(DS.Layout.paletteVisibleRows) * DS.Layout.paletteRowHeight
        + 2 * DS.Layout.paletteHeaderHeight

    var body: some View {
        ScrollViewReader { proxy in
            FadingScrollView(fadeHeight: contentHeight > Self.maxHeight ? DS.Spacing.md : 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if startsSection(index) {
                            header(item.kind)
                        } else {
                            Hairline()
                        }
                        row(item, index: index)
                            .id(item.id)
                    }
                }
            }
            .frame(height: min(contentHeight, Self.maxHeight))
            .onChange(of: selectedIndex) { _, index in
                guard let index, items.indices.contains(index) else { return }
                proxy.scrollTo(items[index].id)
            }
        }
        .padding(DS.Spacing.xs)
        .background(panelShape.fill(DS.Surface.paletteFill))
        .overlay(panelShape.strokeBorder(DS.Stroke.paletteBorder, lineWidth: DS.Stroke.lineWidth))
        .clipShape(panelShape)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.cardCompact, style: .continuous)
    }

    private func startsSection(_ index: Int) -> Bool {
        index == 0 || items[index - 1].kind != items[index].kind
    }

    private var contentHeight: CGFloat {
        let headers = items.indices.filter(startsSection).count
        return CGFloat(items.count) * DS.Layout.paletteRowHeight
            + CGFloat(headers) * DS.Layout.paletteHeaderHeight
            + CGFloat(items.count - headers) * DS.Hairline.standard
    }

    private func header(_ kind: SlashSuggestion.Kind) -> some View {
        let title: String
        switch kind {
        case .command: title = "COMMANDES"
        case .skill: title = "SKILLS"
        case .hermesOnly: title = "HERMES"
        }
        return Text(title)
            .font(DS.Text.sectionHead)
            .tracking(1.5)
            .foregroundStyle(DS.Surface.headerLow)
            .padding(.leading, DS.Spacing.xl)  // aligned on the names: row inset + dot + spacing
            .padding(.bottom, DS.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: DS.Layout.paletteHeaderHeight, alignment: .bottom)
    }

    @ViewBuilder
    private func row(_ item: SlashSuggestion, index: Int) -> some View {
        let isSelected = index == selectedIndex
        let button = Button { onPick(item) } label: {
            HStack(spacing: DS.Spacing.sm) {
                Circle()
                    .fill(isSelected ? AnyShapeStyle(AppColors.accent) : AnyShapeStyle(Color.clear))
                    .frame(width: DS.Spacing.xs, height: DS.Spacing.xs)
                name(item, isSelected: isSelected)
                    .lineLimit(1)
                    .frame(minWidth: DS.Layout.paletteNameWidth, alignment: .leading)
                    .fixedSize()
                Text(item.description)
                    .font(DS.Text.caption)
                    .foregroundStyle(item.isSelectable ? DS.Surface.tertiary : DS.Surface.quaternary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.xs)
            .frame(height: DS.Layout.paletteRowHeight)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Surface.paletteSelection)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!item.isSelectable)
        .onHover { if $0, item.isSelectable { onHover(index) } }

        if item.isSelectable {
            button.pointingHandCursor()
        } else {
            button
        }
    }

    /// "/" + name, the part matching the query in bold: the start for a prefix match
    /// (`/s` of `/sessions`), the matched letters for a match inside the name (`wiki` of `/llm-wiki`).
    private func name(_ item: SlashSuggestion, isSelected: Bool) -> Text {
        let full = "/" + item.name
        let rest = item.isSelectable ? (isSelected ? DS.Surface.primary : DS.Surface.secondary) : DS.Surface.quaternary
        let bold: Range<String.Index>?
        if !item.isSelectable || query.isEmpty {
            bold = nil
        } else if item.name.hasPrefix(query) {
            bold = full.startIndex..<full.index(full.startIndex, offsetBy: query.count + 1)
        } else {
            bold = full.range(of: query)
        }
        guard let bold else { return Text(full).font(DS.Text.labelMono).foregroundStyle(rest) }
        return Text(full[..<bold.lowerBound]).font(DS.Text.labelMono).foregroundStyle(rest)
            + Text(full[bold]).font(DS.Text.labelMonoSemibold).foregroundStyle(DS.Surface.primary)
            + Text(full[bold.upperBound...]).font(DS.Text.labelMono).foregroundStyle(rest)
    }
}
