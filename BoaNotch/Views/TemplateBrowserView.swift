import SwiftUI
import AppKit

struct TemplateBrowserView: View {
    var panelSize: PanelSize = .standard
    var onSelectTemplate: (String) -> Void
    var onCreateOwn: () -> Void

    @State private var selectedTemplate: RoutineTemplate?
    @State private var inputValues: [String: String] = [:]
    @State private var hoveredTemplateId: String?

    private let cardWidth: CGFloat = 220

    var body: some View {
        ZStack {
            if let template = selectedTemplate {
                formScreen(template)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            } else {
                homepageScreen
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .clipped()
    }

    // MARK: - Netflix-style homepage

    private var homepageScreen: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(RoutineCategory.all) { category in
                    categorySection(category)
                }

                createOwnRow
                    .padding(.top, 4)
            }
            // 28pt > FadingScrollView's 24pt fadeHeight so no LazyHStack row
            // ever lands inside the bottom mask gradient (which was clipping
            // the cards' bottom corners visually).
            .padding(.bottom, 28)
        }
    }

    private func categorySection(_ category: RoutineCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(DS.Icon.caption)
                    .foregroundStyle(AppColors.accent)
                Text(category.title)
                    .font(DS.Text.labelSemibold)
                    .foregroundStyle(.primary)
                Text("\(category.templates.count)")
                    .font(DS.Text.micro.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(category.templates) { template in
                        templateCard(template)
                            .frame(width: cardWidth)
                    }
                }
            }
        }
    }

    private var createOwnRow: some View {
        Button {
            onCreateOwn()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(DS.Icon.caption)
                    .foregroundStyle(AppColors.accent)
                Text("Create your own")
                    .font(DS.Text.labelMedium)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DS.Text.microMedium)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DS.Padding.cardProminentH)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(.quaternary.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Template card (matches Routines jobCard visual)

    private func templateCard(_ template: RoutineTemplate) -> some View {
        let isAlert = template.deliver == "local"
        let cardShape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(template.title)
                    .font(DS.Text.labelMedium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if isAlert {
                    Image(systemName: "bell.badge.fill")
                        .font(DS.Icon.caption)
                        .foregroundStyle(AppColors.accent)
                        .accessibilityLabel("Alert routine — notifies in the notch")
                }
            }

            Text(template.subtitle)
                .font(DS.Text.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.gray.opacity(0.35))
                    .frame(width: 7, height: 7)

                Text(template.schedule)
                    .font(DS.Text.microMedium.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.top, 5)
        }
        .padding(.horizontal, DS.Padding.cardProminentH)
        .padding(.vertical, DS.Padding.cardProminentV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape.fill(.quaternary.opacity(0.6)))
        .overlay(
            cardShape
                .fill(hoveredTemplateId == template.id ? AnyShapeStyle(DS.Stroke.hairline) : AnyShapeStyle(Color.clear))
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onHover { over in hoveredTemplateId = over ? template.id : nil }
        .onTapGesture { openTemplate(template) }
        .pointingHandCursor()
        .animation(.easeInOut(duration: 0.15), value: hoveredTemplateId == template.id)
    }

    private func openTemplate(_ template: RoutineTemplate) {
        inputValues = [:]
        for input in template.inputs {
            if case .number(_, let defaultValue) = input.type, let dv = defaultValue {
                inputValues[input.id] = "\(dv)"
            }
            if case .picker(let options) = input.type, let first = options.first {
                inputValues[input.id] = first
            }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            selectedTemplate = template
        }
    }

    // MARK: - Form screen (unchanged)

    private func formScreen(_ template: RoutineTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            backButton(template.title) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedTemplate = nil
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(template.schedule)
            }
            .font(DS.Text.caption)
            .foregroundStyle(.tertiary)

            if template.inputs.isEmpty {
                Spacer()
                Text("No configuration needed — this routine works out of the box.")
                    .font(DS.Text.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                FadingScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(template.inputs) { input in
                            inputField(input)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Button {
                let draft = template.composeDraft(values: inputValues)
                onSelectTemplate(draft)
            } label: {
                Text("Create routine")
                    .font(DS.Text.bodySmallSemibold)
                    .foregroundStyle(allRequiredFilled(template) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if allRequiredFilled(template) {
                            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous).fill(AppColors.accent.opacity(0.35))
                        } else {
                            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous).fill(.quaternary)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(!allRequiredFilled(template))
            .pointingHandCursor()
        }
    }

    @ViewBuilder
    private func inputField(_ input: TemplateInput) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(input.label)
                    .font(DS.Text.caption)
                    .foregroundStyle(.secondary)
                if !input.required {
                    Text("(optional)")
                        .font(DS.Text.micro)
                        .foregroundStyle(.tertiary)
                }
            }

            switch input.type {
            case .freeText(let placeholder):
                TextField(placeholder, text: binding(for: input.id))
                    .textFieldStyle(.plain)
                    .font(DS.Text.label)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.chip).fill(.quaternary))

            case .picker(let options):
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            inputValues[input.id] = option
                        } label: {
                            Text(option)
                                .font(DS.Text.captionMedium)
                                .foregroundStyle(inputValues[input.id] == option ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background {
                                    if inputValues[input.id] == option {
                                        RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous).fill(AppColors.accent.opacity(0.35))
                                    } else {
                                        RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous).fill(.quaternary)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .number(let placeholder, _):
                TextField(placeholder, text: binding(for: input.id))
                    .textFieldStyle(.plain)
                    .font(DS.Text.label)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.chip).fill(.quaternary))
                    .frame(width: 80)

            case .filePath(let placeholder):
                HStack(spacing: 6) {
                    Text(inputValues[input.id] ?? placeholder)
                        .font(DS.Text.label)
                        .foregroundStyle(inputValues[input.id] != nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.chip).fill(.quaternary))

                    Button {
                        pickFile(for: input.id)
                    } label: {
                        Image(systemName: "folder")
                            .font(DS.Text.bodySmall)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.chip).fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
    }

    private func backButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(DS.Text.microBold)
                Text(title)
                    .font(DS.Text.captionMedium)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { inputValues[key] ?? "" },
            set: { inputValues[key] = $0 }
        )
    }

    private func allRequiredFilled(_ template: RoutineTemplate) -> Bool {
        template.inputs.filter(\.required).allSatisfy { input in
            guard let val = inputValues[input.id] else { return false }
            return !val.isEmpty
        }
    }

    private func pickFile(for inputId: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.presentAboveNotch()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                inputValues[inputId] = url.path
            }
        }
    }
}
