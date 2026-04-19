import SwiftUI

struct SearchBarView: View {
    @ObservedObject var searchVM: SearchViewModel
    var onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            TextField("Search...", text: $searchVM.query)
                .textFieldStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.primary)
                .tint(AppColors.accent)
                .focused($isFocused)
                .onSubmit { searchVM.nextMatch() }

            if searchVM.totalMatches > 0 {
                Text("\(searchVM.currentMatchIndex + 1)/\(searchVM.totalMatches)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else if !searchVM.query.isEmpty {
                Text("0")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Button { searchVM.previousMatch() } label: {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(searchVM.totalMatches > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            }
            .buttonStyle(.plain)
            .disabled(searchVM.totalMatches == 0)

            Button { searchVM.nextMatch() } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(searchVM.totalMatches > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            }
            .buttonStyle(.plain)
            .disabled(searchVM.totalMatches == 0)

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
        .padding(.horizontal, 42)
        .padding(.top, 36)
        .padding(.bottom, 4)
        .onAppear { isFocused = true }
    }
}
