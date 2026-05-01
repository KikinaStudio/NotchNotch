import Foundation

/// Editorial v1 catalog of user-facing capabilities. Order here is the order
/// shown in the Skills tab.
///
/// To add a brand entry: pick a Simple Icons slug, add it to
/// `scripts/fetch-brand-icons.sh`, re-run that script, then append a
/// `CuratedSkill` here. The build scripts copy `Resources/BrandIcons/*.svg`
/// flat into `Contents/Resources/` automatically.
enum CuratedSkillCatalog {
    static let all: [CuratedSkill] = [
        CuratedSkill(
            id: "spotify",
            displayName: "Spotify",
            descriptionFR: "Lance ta musique, gère tes playlists, contrôle la lecture",
            icon: .brand(slug: "spotify", hex: "#1ED760"),
            detection: .hermesAuthProvider("spotify"),
            connectAction: .external(URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/spotify")!),
            promptExamplesFR: [
                "Lance Miles Davis",
                "Mets pause",
                "Qu'est-ce qui joue ?"
            ],
            mappedSkillIDs: ["media/spotify"]
        ),
        CuratedSkill(
            id: "google-calendar",
            displayName: "Google Agenda",
            descriptionFR: "Crée, lit et modifie tes événements de calendrier",
            icon: .brand(slug: "googlecalendar", hex: "#4285F4"),
            detection: .googleScope("calendar"),
            connectAction: .oauth(.google),
            promptExamplesFR: [
                "Mes rendez-vous demain ?",
                "Bloque jeudi 14h-15h pour un point",
                "Déplace le déjeuner à 13h"
            ],
            mappedSkillIDs: ["productivity/google-workspace"]
        ),
        CuratedSkill(
            id: "gmail",
            displayName: "Gmail",
            descriptionFR: "Lit, recherche et envoie des emails",
            icon: .brand(slug: "gmail", hex: "#EA4335"),
            detection: .googleScope("gmail.modify"),
            connectAction: .oauth(.google),
            promptExamplesFR: [
                "Mes emails non lus",
                "Cherche les emails de Marie cette semaine",
                "Envoie un mail à Paul pour reporter à demain"
            ],
            mappedSkillIDs: ["productivity/google-workspace"]
        ),
        CuratedSkill(
            id: "google-drive",
            displayName: "Google Drive",
            descriptionFR: "Cherche et lit tes fichiers Drive, Docs et Sheets",
            icon: .brand(slug: "googledrive", hex: "#4285F4"),
            detection: .googleScope("drive"),
            connectAction: .oauth(.google),
            promptExamplesFR: [
                "Trouve le doc sur le projet X",
                "Résume le dernier rapport trimestriel",
                "Liste mes derniers Sheets"
            ],
            mappedSkillIDs: ["productivity/google-workspace"]
        ),
        CuratedSkill(
            id: "notion",
            displayName: "Notion",
            descriptionFR: "Lit et modifie tes pages, bases de données et blocs Notion",
            icon: .brand(slug: "notion", hex: "#000000"),
            detection: .envVar("NOTION_API_KEY"),
            connectAction: .apiKeyInput(
                envVarName: "NOTION_API_KEY",
                helpText: "Crée une intégration sur ta page Notion, copie le secret (commence par ntn_), partage tes pages avec elle",
                helpURL: URL(string: "https://notion.so/my-integrations")
            ),
            promptExamplesFR: [
                "Crée une page dans ma base de tâches",
                "Cherche mes notes sur le projet X",
                "Lis ma page d'objectifs trimestriels"
            ],
            mappedSkillIDs: ["productivity/notion"]
        ),
        CuratedSkill(
            id: "google-meet",
            displayName: "Google Meet",
            descriptionFR: "Ajoute un lien Meet à tes événements de calendrier",
            icon: .brand(slug: "googlemeet", hex: "#00897B"),
            detection: .googleScope("calendar"),
            connectAction: .oauth(.google),
            promptExamplesFR: [
                "Programme un Meet avec Paul demain à 10h",
                "Ajoute un Meet à mon prochain rendez-vous"
            ],
            mappedSkillIDs: ["productivity/google-workspace"]
        )
    ]

    /// Set of all Hermes `SkillInfo.id`s referenced by the catalog. Used to
    /// filter zone 2 (technical skills) so curated cards don't duplicate.
    static let mappedSkillIDs: Set<String> = Set(all.flatMap(\.mappedSkillIDs))
}
