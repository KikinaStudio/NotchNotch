import Foundation

/// Editorial v1 catalog of capabilities that operate on the Mac itself.
/// Distinct from `CuratedSkillCatalog` which lists external-service skills.
///
/// To add an entry: define a new `SystemCapability` with its detection rule,
/// prompt examples, and docs link, then append it here. Install flow lives in
/// the matching service (e.g. `ComputerUseService` for `computer_use`).
enum SystemCapabilityCatalog {
    static let all: [SystemCapability] = [
        SystemCapability(
            id: "computer-use",
            displayName: "Contrôle du Mac",
            descriptionFR: "Laisse l'agent utiliser tes apps : clics, frappe, lecture d'écran, en arrière-plan",
            icon: .sfSymbol(name: "macwindow.and.cursorarrow"),
            detection: .binaryOnPath("cua-driver"),
            promptExamplesFR: [
                "Trouve mon dernier mail Stripe et résume-le",
                "Range mon dossier Téléchargements par date",
                "Active le mode sombre dans les Préférences Système"
            ],
            docsURL: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/computer-use")!
        )
    ]
}
