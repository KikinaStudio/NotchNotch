import SwiftUI

struct SearchBarView: View {
    @ObservedObject var searchVM: SearchViewModel
    var onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))

            TextField("Search...", text: $searchVM.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .tint(AppColors.accent)
                .focused($isFocused)
                .onSubmit { searchVM.nextMatch() }

            if searchVM.totalMatches > 0 {
                Text("\(searchVM.currentMatchIndex + 1)/\(searchVM.totalMatches)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            } else if !searchVM.query.isEmpty {
                Text("0")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }

            Button { searchVM.previousMatch() } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(searchVM.totalMatches > 0 ? 0.5 : 0.15))
            }
            .buttonStyle(.plain)
            .disabled(searchVM.totalMatches == 0)

            Button { searchVM.nextMatch() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(searchVM.totalMatches > 0 ? 0.5 : 0.15))
            }
            .buttonStyle(.plain)
            .disabled(searchVM.totalMatches == 0)

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 38)
        .padding(.top, 36)
        .padding(.bottom, 4)
        .onAppear { isFocused = true }
    }
}
