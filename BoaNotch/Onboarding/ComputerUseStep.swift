import SwiftUI
import AppKit

/// Step optionnelle proposant à l'user de donner les commandes du Mac à
/// son agent (cua-driver, Hermes 0.14+). La step est skippable à toutes
/// les phases — l'user peut toujours revenir via Settings ou la card
/// Brain (livrées Session 2). Quatre phases dérivées de
/// `ComputerUseService.shared` :
///
/// - `.notInstalled` + pas en cours d'install → pitch (titre, description,
///   3 rows pédagogiques, "Plus tard" / "Activer")
/// - `isInstalling == true` ET pas d'erreur → spinner + progress
/// - `installError != nil` → bloc inset + "Réessayer" / "Plus tard"
/// - `.installedPendingPermissions` → 3 deeplinks macOS + "C'est bon" /
///   "Plus tard"
/// - `.ready` → "C'est déjà actif" + Continuer
///
/// `install()` est non-throwing : les erreurs remontent via le
/// `@Published var installError` du service, observable directement.
/// `confirmPermissions()` set `state = .ready` synchrone côté service,
/// pas besoin de `refreshState()` derrière.
struct ComputerUseStep: View {
    @ObservedObject var onboardingVM: OnboardingViewModel
    @ObservedObject private var service = ComputerUseService.shared

    var body: some View {
        Group {
            if service.installError != nil {
                errorPhase
            } else if service.isInstalling {
                installingPhase
            } else {
                switch service.state {
                case .notInstalled, .installing:
                    pitchPhase
                case .installedPendingPermissions:
                    permissionsPhase
                case .ready:
                    readyPhase
                }
            }
        }
    }

    // MARK: - Phase: pitch

    private var pitchPhase: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Donner les commandes du Mac à ton agent")
                .font(DS.Text.titleSmall)
                .foregroundStyle(DS.Surface.primary)
                .padding(.bottom, 6)

            Text("Ton agent peut utiliser tes apps comme tu le ferais : ouvrir Mail, ranger des fichiers, naviguer dans Safari. Tout se passe en arrière-plan, ton curseur ne bouge pas.")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    pitchRow(icon: "eye.slash",
                             title: "Discret",
                             detail: "Ton curseur et ton focus clavier ne changent pas.")
                    pitchRow(icon: "lock.shield",
                             title: "Sûr",
                             detail: "L'agent ne peut pas taper ton mot de passe ni `sudo`.")
                    pitchRow(icon: "slider.horizontal.3",
                             title: "Sous contrôle",
                             detail: "Tu peux exiger une confirmation avant chaque action.")
                }
            }

            HStack(spacing: 16) {
                skipButton

                Spacer()

                OnboardingButton("Activer") {
                    Task { await ComputerUseService.shared.install() }
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Phase: installing

    private var installingPhase: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Donner les commandes du Mac à ton agent")
                .font(DS.Text.titleSmall)
                .foregroundStyle(DS.Surface.primary)

            SpinningRing()

            Text(service.installProgress)
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.tertiary)
                .animation(.easeInOut(duration: 0.3), value: service.installProgress)

            Spacer()
        }
    }

    // MARK: - Phase: install error

    private var errorPhase: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Donner les commandes du Mac à ton agent")
                .font(DS.Text.titleSmall)
                .foregroundStyle(DS.Surface.primary)
                .padding(.bottom, 6)

            Text("L'installation a échoué")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.tertiary)
                .padding(.bottom, 14)

            ScrollView {
                Text(service.installError ?? "")
                    .font(DS.Text.nanoMono)
                    .foregroundStyle(DS.Surface.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 80)
            .padding(8)
            .background(.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.05), lineWidth: 0.5)
            )

            Spacer()

            HStack(spacing: 16) {
                skipButton

                Spacer()

                OnboardingButton("Réessayer") {
                    Task {
                        ComputerUseService.shared.installError = nil
                        await ComputerUseService.shared.install()
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Phase: permissions

    private var permissionsPhase: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Une dernière chose")
                .font(DS.Text.titleSmall)
                .foregroundStyle(DS.Surface.primary)
                .padding(.bottom, 6)

            Text("Autorise macOS à laisser ton agent contrôler ces capacités.")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            VStack(spacing: 8) {
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
            }

            Spacer()

            HStack(spacing: 16) {
                skipButton

                Spacer()

                OnboardingButton("C'est bon") {
                    ComputerUseService.shared.confirmPermissions()
                    onboardingVM.advance()
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Phase: ready

    private var readyPhase: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("C'est déjà actif")
                .font(DS.Text.titleSmall)
                .foregroundStyle(DS.Surface.primary)

            Text("Ton agent peut déjà utiliser ton Mac.")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Surface.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Spacer()
                OnboardingButton("Continuer") { onboardingVM.advance() }
            }
        }
    }

    // MARK: - Helpers

    private var skipButton: some View {
        Button { onboardingVM.advance() } label: {
            Text("Plus tard")
                .font(DS.Text.micro)
                .foregroundStyle(DS.Surface.secondary)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func pitchRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(DS.Icon.inline)
                .foregroundStyle(AppColors.accent.opacity(0.7))
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Text.captionMedium)
                    .foregroundStyle(.white.opacity(0.75))
                Text(detail)
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.Surface.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
}
