import SwiftUI
import AppKit

/// Detail view for a `SystemCapability` (currently only "Contrôle du Mac").
/// Mirrors `CuratedSkillDetailView`'s structure (overlay presentation, back
/// chevron, FadingScrollView, hero + status + description + examples +
/// action) but diverges on the state machine: a `SystemCapability` has 4
/// states (notInstalled / installing / installedPendingPermissions / ready)
/// vs. CuratedSkill's binary connected/available.
///
/// **NotchNotch cannot verify cua-driver permissions programmatically** —
/// cua-driver is a separate binary with its own bundle-id, and macOS TCC
/// grants are scoped per bundle. The "C'est bon" button in the
/// `.installedPendingPermissions` action zone is a UI-side act of faith:
/// we trust the user walked through the 3 panels and persist their
/// confirmation in UserDefaults (`ComputerUseService.confirmPermissions`).
struct ComputerUseDetailView: View {
    let capability: SystemCapability
    @ObservedObject var service: ComputerUseService
    let onBack: () -> Void
    let onAskExample: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(DS.Text.captionSemibold)
                    Text(capability.displayName)
                        .font(DS.Text.bodySmallMedium)
                        .lineLimit(1)
                }
                .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .padding(.bottom, 14)

            FadingScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    statusLine
                    Text(capability.descriptionFR)
                        .font(DS.Text.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    promptExamplesSection

                    actionSection
                        .padding(.top, 4)

                    securityNote
                        .padding(.top, 4)
                }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Hero + status

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandIconView(kind: capability.icon, size: 40, tint: heroTint)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.displayName)
                    .font(DS.Text.title)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
    }

    private var heroTint: Color? {
        switch service.state {
        case .notInstalled: return Color.primary.opacity(0.35)
        case .installing: return AppColors.accent
        case .installedPendingPermissions: return Color.orange
        case .ready: return AppColors.accent
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle().fill(statusDotStyle).frame(width: 7, height: 7)
            Text(statusLabel)
                .font(DS.Text.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusDotStyle: AnyShapeStyle {
        switch service.state {
        case .notInstalled: return AnyShapeStyle(Color.white.opacity(0.3))
        case .installing: return AnyShapeStyle(AppColors.accent.opacity(0.85))
        case .installedPendingPermissions: return AnyShapeStyle(Color.orange.opacity(0.9))
        case .ready: return AnyShapeStyle(Color.green.opacity(0.85))
        }
    }

    private var statusLabel: String {
        switch service.state {
        case .notInstalled: return "Pas installé"
        case .installing: return "Installation en cours…"
        case .installedPendingPermissions: return "Permissions requises"
        case .ready: return "Actif"
        }
    }

    // MARK: - Prompt examples

    private var promptExamplesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(promptExamplesHeader)
                .font(DS.Text.sectionHead)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DS.Surface.headerLow)
                .padding(.bottom, 2)

            ForEach(capability.promptExamplesFR, id: \.self) { example in
                Button {
                    if isInteractive { onAskExample(example) }
                } label: {
                    HStack(spacing: 8) {
                        Text(example)
                            .font(DS.Text.bodySmall)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isInteractive {
                            Image(systemName: "arrow.up.right")
                                .font(DS.Icon.chevron)
                                .foregroundStyle(AppColors.accent.opacity(0.55))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(.quaternary.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isInteractive)
                .pointingHandCursor()
            }
        }
    }

    private var promptExamplesHeader: String {
        switch service.state {
        case .ready: return "Essaie"
        default: return "Tu pourras lui demander"
        }
    }

    private var isInteractive: Bool {
        service.state == .ready
    }

    // MARK: - Action section (state-dependent)

    @ViewBuilder
    private var actionSection: some View {
        switch service.state {
        case .notInstalled:
            notInstalledActions
        case .installing:
            installingActions
        case .installedPendingPermissions:
            pendingPermissionsActions
        case .ready:
            readyActions
        }
    }

    private var notInstalledActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Task { await service.install() }
                } label: {
                    Text("Installer")
                }
                .buttonStyle(PrimaryButtonStyle())
                .pointingHandCursor()

                Button {
                    NSWorkspace.shared.open(capability.docsURL)
                } label: {
                    Text("Voir la doc")
                        .font(DS.Text.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                Spacer()
            }

            if let err = service.installError {
                installErrorBlock(err)
            }
        }
    }

    private var installingActions: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.85)
            if !service.installProgress.isEmpty {
                Text(service.installProgress)
                    .font(DS.Text.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var pendingPermissionsActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Une dernière chose : autorise macOS")
                .font(DS.Text.bodyMedium)
                .foregroundStyle(.primary)

            permissionRow(
                icon: "accessibility",
                label: "Accessibilité",
                action: service.openAccessibilitySettings
            )
            permissionRow(
                icon: "rectangle.dashed.badge.record",
                label: "Enregistrement d'écran",
                action: service.openScreenRecordingSettings
            )
            permissionRow(
                icon: "gearshape.2.fill",
                label: "Automation",
                action: service.openAutomationSettings
            )

            HStack {
                Spacer()
                Button {
                    service.confirmPermissions()
                    onBack()
                } label: {
                    Text("C'est bon")
                }
                .buttonStyle(PrimaryButtonStyle())
                .pointingHandCursor()
            }
            .padding(.top, 4)
        }
    }

    private var readyActions: some View {
        // Nothing to do — the prompt examples above ARE the call-to-action.
        // No uninstall flow in v1 (out of scope, will revisit if asked).
        EmptyView()
    }

    private func permissionRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(DS.Text.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(label)
                    .font(DS.Text.bodySmall)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DS.Icon.chevron)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func installErrorBlock(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.Text.caption)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(DS.Text.micro)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await service.install() }
                } label: {
                    Text("Réessayer")
                        .font(DS.Text.micro.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
    }

    // MARK: - Security note

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(DS.Text.caption)
                .foregroundStyle(.tertiary)
            Text("Ton curseur ne bouge pas, ton focus clavier non plus. L'agent ne peut pas taper ton mot de passe, vider la corbeille, ou exécuter `sudo`.")
                .font(DS.Text.micro)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
