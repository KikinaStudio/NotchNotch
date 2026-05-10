import SwiftUI

struct SearchBarView: View {
    @ObservedObject var searchVM: SearchViewModel
    var onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(DS.Text.bodySmall)
                .foregroundStyle(.tertiary)

            TextField("Search...", text: $searchVM.query)
                .textFieldStyle(.plain)
                .font(DS.Text.label)
                .foregroundStyle(.primary)
                .tint(AppColors.accent)
                .focused($isFocused)
                .onSubmit { searchVM.nextMatch() }

            if searchVM.totalMatches > 0 {
                Text("\(searchVM.currentMatchIndex + 1)/\(searchVM.totalMatches)")
                    .font(DS.Text.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else if !searchVM.query.isEmpty {
                Text("0")
                    .font(DS.Text.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Button { searchVM.previousMatch() } label: {
                Image(systemName: "chevron.up")
                    .font(DS.Text.captionMedium)
                    .foregroundStyle(searchVM.totalMatches > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            }
            .buttonStyle(.plain)
            .disabled(searchVM.totalMatches == 0)

            Button { searchVM.nextMatch() } label: {
                Image(systemName: "chevron.down")
                    .font(DS.Text.captionMedium)
                    .foregroundStyle(searchVM.totalMatches > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            }
            .buttonStyle(.plain)
            .disabled(searchVM.totalMatches == 0)

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(DS.Text.captionMedium)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Padding.inputH)
        .padding(.vertical, DS.Padding.inputV)
        .background(RoundedRectangle(cornerRadius: DS.Radius.button).fill(.quaternary.opacity(0.6)))
        .padding(.horizontal, 42)
        .padding(.top, 36)
        .padding(.bottom, 4)
        .onAppear { isFocused = true }
    }
}
