import SwiftUI
import AppKit

struct TemplateBrowserView: View {
    var onSelectTemplate: (String) -> Void
    var onCreateOwn: () -> Void

    @State private var selectedCategory: RoutineCategory?
    @State private var selectedTemplate: RoutineTemplate?
    @State private var inputValues: [String: String] = [:]

    var body: some View {
        ZStack {
            if let template = selectedTemplate {
                formScreen(template)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            } else if let category = selectedCategory {
                templateListScreen(category)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            } else {
                categoriesScreen
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .clipped()
    }

    // MARK: - Screen 1: Categories

    private var categoriesScreen: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick a category, or describe your own in the chat.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(RoutineCategory.all) { category in
                        categoryRow(category)
                    }

                    // Create your own
                    Button {
                        onCreateOwn()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.body)
                                .foregroundStyle(AppColors.accent.opacity(0.6))
                                .frame(width: 20)

                            Text("Create your own")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(.quinary)
                        )
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
    }

    private func categoryRow(_ category: RoutineCategory) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .font(.body)
                    .foregroundStyle(AppColors.accent.opacity(0.7))
                    .frame(width: 20)

                Text(category.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(category.templates.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(.quinary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Screen 2: Template list

    private func templateListScreen(_ category: RoutineCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            backButton(category.title) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedCategory = nil
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(category.templates) { template in
                        templateRow(template)
                    }
                }
            }
        }
    }

    private func templateRow(_ template: RoutineTemplate) -> some View {
        Button {
            inputValues = [:]
            // Pre-fill defaults for number inputs
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
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: template.icon)
                    .font(.body)
                    .foregroundStyle(AppColors.accent.opacity(0.7))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(template.title)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.primary)
                        if template.deliver == "local" {
                            Image(systemName: "bell.badge")
                                .font(.caption2)
                                .foregroundStyle(AppColors.accent)
                        }
                    }

                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(.quinary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Screen 3: Form

    private func formScreen(_ template: RoutineTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            backButton(template.title) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedTemplate = nil
                }
            }

            // Schedule info
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(template.schedule)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            if template.inputs.isEmpty {
                Spacer()
                Text("No configuration needed — this routine works out of the box.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(template.inputs) { input in
                            inputField(input)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            // Create button
            Button {
                let draft = template.composeDraft(values: inputValues)
                onSelectTemplate(draft)
            } label: {
                Text("Create routine")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(allRequiredFilled(template) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if allRequiredFilled(template) {
                            Capsule().fill(AppColors.accent.opacity(0.35))
                        } else {
                            Capsule().fill(.quaternary)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(!allRequiredFilled(template))
            .pointingHandCursor()
        }
    }

    // MARK: - Input fields

    @ViewBuilder
    private func inputField(_ input: TemplateInput) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(input.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !input.required {
                    Text("(optional)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            switch input.type {
            case .freeText(let placeholder):
                TextField(placeholder, text: binding(for: input.id))
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

            case .picker(let options):
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            inputValues[input.id] = option
                        } label: {
                            Text(option)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(inputValues[input.id] == option ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background {
                                    if inputValues[input.id] == option {
                                        Capsule().fill(AppColors.accent.opacity(0.35))
                                    } else {
                                        Capsule().fill(.quaternary)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .number(let placeholder, _):
                TextField(placeholder, text: binding(for: input.id))
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    .frame(width: 80)

            case .filePath(let placeholder):
                HStack(spacing: 6) {
                    Text(inputValues[input.id] ?? placeholder)
                        .font(.callout)
                        .foregroundStyle(inputValues[input.id] != nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

                    Button {
                        pickFile(for: input.id)
                    } label: {
                        Image(systemName: "folder")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
    }

    // MARK: - Helpers

    private func backButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.caption2.weight(.bold))
                Text(title)
                    .font(.caption.weight(.medium))
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
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                inputValues[inputId] = url.path
            }
        }
    }
}
