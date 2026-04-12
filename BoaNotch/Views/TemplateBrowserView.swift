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
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
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
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.accent.opacity(0.5))
                                .frame(width: 20)

                            Text("Create your own")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.accent.opacity(0.6))
                    .frame(width: 20)

                Text(category.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text("\(category.templates.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.2))

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.15))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
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
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.accent.opacity(0.6))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Text(template.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.15))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
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
                    .font(.system(size: 9))
                Text(template.schedule)
                    .font(.system(size: 10))
            }
            .foregroundStyle(.white.opacity(0.3))

            if template.inputs.isEmpty {
                Spacer()
                Text("No configuration needed — this routine works out of the box.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(allRequiredFilled(template) ? .white : .white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(allRequiredFilled(template) ? AppColors.accent.opacity(0.3) : .white.opacity(0.06))
                    .clipShape(Capsule())
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
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                if !input.required {
                    Text("(optional)")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }

            switch input.type {
            case .freeText(let placeholder):
                TextField(placeholder, text: binding(for: input.id))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

            case .picker(let options):
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            inputValues[input.id] = option
                        } label: {
                            Text(option)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(inputValues[input.id] == option ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(inputValues[input.id] == option ? AppColors.accent.opacity(0.3) : .white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .number(let placeholder, _):
                TextField(placeholder, text: binding(for: input.id))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 80)

            case .filePath(let placeholder):
                HStack(spacing: 6) {
                    Text(inputValues[input.id] ?? placeholder)
                        .font(.system(size: 10))
                        .foregroundStyle(inputValues[input.id] != nil ? .white.opacity(0.7) : .white.opacity(0.25))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        pickFile(for: input.id)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
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
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.4))
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
