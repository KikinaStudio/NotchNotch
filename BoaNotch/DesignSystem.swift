import SwiftUI
import CoreGraphics

/// Design tokens NotchNotch.
/// Source de vérité unique pour tailles de police, ShapeStyles, rayons, espacements,
/// hairlines, animations. Toute UI doit puiser ici plutôt que de hardcoder.
/// Voir CLAUDE.md, section "Design system policy".
///
/// Règle d'or: si une vue a besoin d'une valeur hors catalogue, on AJOUTE le token
/// ici puis on l'utilise. On ne hardcode jamais en call site.
///
/// Le catalogue v1 est volontairement minimal. Les tokens supplémentaires
/// arriveront au cas par cas pendant les sessions de migration (Onboarding →
/// MessageBubble → reste), pas préemptivement.
enum DS {

    // MARK: - Typography
    /// Tailles et poids texte. Noms sémantiques (rôle), pas descriptifs (taille).
    enum Text {
        /// 18pt semibold. État affirmatif onboarding (ReadyStep "You're all set").
        /// Pour les titres des autres étapes onboarding, voir `titleSmall`.
        static let title         = Font.system(size: 18, weight: .semibold)
        /// 16pt semibold. Titre d'étape onboarding standard
        /// (Privacy / Install / Choose / Telegram).
        static let titleSmall    = Font.system(size: 16, weight: .semibold)
        /// 14pt regular. Texte de lecture chat principal.
        /// Note: pour MessageBubble, voir `messageBodySize` (scalé par textSize.medium=12 / large=15).
        static let body          = Font.system(size: 14)
        /// 14pt medium. Titre de ligne d'App / titre de capacité dans la liste
        /// Tools (App row Section 1, CapabilityCard Section 2 + catalogue).
        /// Plus affirmé que `body` sans monter à `title`/`titleSmall`.
        static let bodyMedium    = Font.system(size: 14, weight: .medium)
        /// 13pt regular. Blockquotes, file card titles, streaming cursor.
        static let bodySmall     = Font.system(size: 13)
        /// 12pt regular. CTA labels, code blocks inline.
        static let label         = Font.system(size: 12)
        /// 12pt medium. Boutons CTA primaires onboarding (OnboardingButton/WideButton),
        /// labels d'erreur affirmés.
        static let labelMedium   = Font.system(size: 12, weight: .medium)
        /// 11pt regular. Labels UI standards, hints, status text.
        static let caption       = Font.system(size: 11)
        /// 11pt medium. Titre de carte sélectionnée (model card name, privacy row title).
        static let captionMedium = Font.system(size: 11, weight: .medium)
        /// 10pt regular. Métadonnées faibles, labels secondaires onboarding.
        static let micro         = Font.system(size: 10)
        /// 10pt medium. Étiquettes affirmées (banner d'erreur, tag de routine active).
        static let microMedium   = Font.system(size: 10, weight: .medium)
        /// 9pt regular. Métadonnées très faibles, fine print, descriptions discrètes.
        static let nano          = Font.system(size: 9)
        /// 12pt monospaced. Code blocks dans MessageBubble.
        static let codeBlock     = Font.system(size: 12, design: .monospaced)
        /// 11pt monospaced. Contenu thinking/tool calls collapsé, paths sous file/image cards.
        static let captionMono   = Font.system(size: 11, design: .monospaced)
        /// 10pt monospaced. Tokens, ID, valeurs techniques inline (champ token Telegram).
        static let microMono     = Font.system(size: 10, design: .monospaced)
        /// 9pt monospaced. Texte technique très faible (logs erreurs InstallHermes).
        static let nanoMono      = Font.system(size: 9, design: .monospaced)
        /// 10pt monospaced bold. Section headers UPPERCASE et badges numérotés (step rows).
        static let sectionHead   = Font.system(size: 10, weight: .bold, design: .monospaced)
        /// 8pt monospaced medium. Badges discrets (statuts, tags `Free`/`Pro`).
        static let badge         = Font.system(size: 8, weight: .medium, design: .monospaced)
        /// 13pt serif regular. Marque brand `§` en tête des MemoryCards (Brain panel).
        /// Glyphe signature, ne pas réutiliser pour autre chose.
        static let serifMark     = Font.system(size: 13, weight: .regular, design: .serif)
    }

    // MARK: - Icon
    /// Tailles d'icônes SF Symbols. Séparé de DS.Text pour clarté sémantique
    /// (les icônes sont stylées via Font techniquement mais ne sont pas du texte).
    enum Icon {
        /// 28pt light. Hero status icon (checkmark "all set" ReadyStep).
        static let hero      = Font.system(size: 28, weight: .light)
        /// 22pt regular. Large status icon (wrench InstallHermes).
        static let large     = Font.system(size: 22)
        /// 18pt. Icône CTA primaire (send button arrow.up.circle.fill) ou status icon error.
        static let primary   = Font.system(size: 18)
        /// 13pt hierarchical. Glyph type d'une routine card (silent/digest/alert).
        /// Discret : la distinction est portée par la forme du glyph, pas la taille.
        static let routineType = Font.system(size: 13)
        /// 14pt medium. Icônes secondaires (input bar paperclip / mic). Cf CLAUDE.md "Icon sizing".
        static let secondary = Font.system(size: 14, weight: .medium)
        /// 13pt medium. Icônes du top bar du notch (burgers, resize). Cf CLAUDE.md "Icon sizing".
        static let topBar    = Font.system(size: 13, weight: .medium)
        /// 13pt regular. Icônes inline list rows (privacy bullets).
        static let inline    = Font.system(size: 13)
        /// 12pt regular. Icônes intégrées dans bouton wide.
        static let glyph     = Font.system(size: 12)
        /// 11pt regular. Petit glyphe inline (bell.badge.fill marquant les routines alert).
        static let caption   = Font.system(size: 11)
        /// 9pt regular. Petite icône inline (status checkmark "Connected").
        static let mini      = Font.system(size: 9)
        /// 8pt medium. Chevrons inline (back arrow onboarding container).
        static let chevron   = Font.system(size: 8, weight: .medium)
        /// 8pt bold. Chevrons disclosure pour toggles MessageBubble (thinking, tool calls).
        /// Plus marqué que `chevron` pour visibilité affordance "déplier/replier".
        static let chevronBold = Font.system(size: 8, weight: .bold)
    }

    // MARK: - Surface (foreground / fill ShapeStyles)
    /// Wrapper ShapeStyle natifs pour usage uniforme.
    /// Préférence absolue pour les ShapeStyles SwiftUI natifs (.primary, .secondary,
    /// .tertiary, .quaternary, .separator) plutôt que .white.opacity(x).
    /// Cf CLAUDE.md: "use semantic ShapeStyles ... rather than hardcoded .white.opacity(x)".
    ///
    /// Wrappés en AnyShapeStyle pour composer directement dans les ternaires
    /// conditionnels (.foregroundStyle(isActive ? DS.Surface.primary : DS.Surface.secondary)).
    enum Surface {
        /// Texte titre, body principal. ShapeStyle natif .primary (≈ 88% white sur fond noir).
        static let primary    = AnyShapeStyle(.primary)
        /// Texte secondaire, body lecture. ShapeStyle natif .secondary (≈ 55%).
        static let secondary  = AnyShapeStyle(.secondary)
        /// Texte tertiaire, hints, métadonnées. Blanc 33%.
        static let tertiary   = AnyShapeStyle(Color.white.opacity(0.33))
        /// Texte très faible, désactivé, fills cartes routines. Blanc 24%.
        static let quaternary = AnyShapeStyle(Color.white.opacity(0.24))
        /// Hairlines dividers. ShapeStyle natif .separator.
        static let separator  = AnyShapeStyle(.separator)
    }

    // MARK: - Status
    /// Couleurs sémantiques pour pastilles d'état (succès / échec).
    /// Wrappées en AnyShapeStyle pour composer avec .foregroundStyle / .fill
    /// dans les ternaires conditionnels. Doctrine : aucune vue ne hardcode
    /// `.green` / `.red` ; passer par ces tokens.
    enum Status {
        /// Vert ~85% — completed dot, succès non bruyant.
        static let success = AnyShapeStyle(Color.green.opacity(0.85))
        /// Rouge ~85% — failed dot, erreurs.
        static let failure = AnyShapeStyle(Color.red.opacity(0.85))
    }

    // MARK: - Stroke (hairlines)
    /// Pour bordures et stroke d'overlay où on a besoin de contrôle fin sur l'opacité.
    /// Préférer DS.Surface.separator quand un ShapeStyle natif suffit.
    enum Stroke {
        /// 0.06 — hairline standard list rows et cards (CLAUDE.md "1pt hairline dividers").
        static let hairline = Color.white.opacity(0.06)
        /// Épaisseur trait standard pour overlays.
        static let lineWidth: CGFloat = 0.5
    }

    // MARK: - Radius
    /// Rayons d'arrondi.
    enum Radius {
        /// 6pt. Petits éléments (input fields, code blocks, error frames).
        static let chip = CGFloat(6)
        /// 8pt. Boutons CTA, segmented controls, search fields.
        /// Valeur largement dominante dans le repo (BrainView, Settings,
        /// Routines, TemplateBrowser).
        static let button = CGFloat(8)
        /// 10pt. Card compacte (CapabilityCard, AppCard Tools tab).
        /// Plus subtil que `card`, signe une matière "rangée à plat".
        static let cardCompact = CGFloat(10)
        /// 12pt. Cartes prominentes routines/memory/templates, gros containers
        /// (CLAUDE.md "12pt continuous rounded").
        static let card = CGFloat(12)
    }

    // MARK: - Spacing
    /// Espacements génériques (gaps entre éléments). Pour les paddings de
    /// composants standardisés (cards, rows, boutons), voir DS.Padding.
    enum Spacing {
        /// 4pt — gap intra-élément (icône + label inline, espace serré dans un row).
        static let xs = CGFloat(4)
        /// 8pt — gap items modérément liés, padding intérieur input field.
        static let sm = CGFloat(8)
        /// 10pt — gap dense list, padding row standard.
        static let md = CGFloat(10)
        /// 14pt — gap cards et rows denses.
        static let lg = CGFloat(14)
        /// 16pt — gap inter-sections.
        static let xl = CGFloat(16)
        /// 20pt — gap entre zones majeures (Memory → Wiki dans BrainView).
        static let xxl = CGFloat(20)
        /// 24pt — gap inter-sections Tools tab (Apps → Capacités).
        static let xxxl = CGFloat(24)

        /// Alias historique de `md` (10pt). Conservé pour compatibilité ;
        /// sera retiré une fois les call-sites migrés vers `DS.Spacing.md`.
        static let row = CGFloat(10)
        /// Alias historique de `xl` (16pt). Conservé pour compatibilité ;
        /// sera retiré une fois les call-sites migrés vers `DS.Spacing.xl`.
        static let section = CGFloat(16)
    }

    // MARK: - Padding presets
    /// Presets de paddings pour composants standardisés. Distincts de
    /// `DS.Spacing` qui couvre les gaps génériques entre éléments.
    /// Nommage par rôle (card, button, segment, input) plutôt que par
    /// échelle, pour cohérence avec la typo (`title`, `body`, `caption`).
    ///
    /// Doctrine : tout nouveau composant utilise un de ces presets ou
    /// AJOUTE un nouveau preset ici. Pas de padding inline en call site.
    enum Padding {
        /// 14H × 12V — card compacte, lecture dense (CapabilityCard, usages
        /// Tools tab Section 2 et catalogue SkillsHub).
        static let cardCompactH = CGFloat(14)
        static let cardCompactV = CGFloat(12)

        /// 14H × 16V — card prominente, contenu primaire (memoryCardCompact
        /// dans BrainView, templateCard dans TemplateBrowser, MissionsActivityBanner).
        static let cardProminentH = CGFloat(14)
        static let cardProminentV = CGFloat(16)

        /// 14H × 6V — row dense de liste avec hairline divider entre items
        /// (routineRow, futurs sessionRow et memoryRow). À combiner avec
        /// DS.Layout.rowMinHeight.
        static let rowH = CGFloat(14)
        static let rowV = CGFloat(6)

        /// 12H × 6V — bouton CTA et action standard (browseButton,
        /// externalLinkButton, "Save API key", "Enregistrer", futur PrimaryButton).
        static let buttonH = CGFloat(12)
        static let buttonV = CGFloat(6)

        /// 12H × 5V — segmented control / picker pill (segmentedButton dans
        /// SettingsView, providerSegment dans ConnectProviderStep, futur
        /// SegmentedButton). Plus serré que `button` pour densité d'un groupe.
        static let segmentH = CGFloat(12)
        static let segmentV = CGFloat(5)

        /// 10H × 6V — input field stylisé (search field BrainView/History,
        /// futur SearchField). Le champ texte respire moins qu'un bouton parce
        /// que le label est saisi par l'utilisateur, pas affiché statiquement.
        static let inputH = CGFloat(10)
        static let inputV = CGFloat(6)
    }

    // MARK: - Hairline weights
    /// Épaisseurs traits / dividers.
    enum Hairline {
        /// 0.5pt — hairline standard SwiftUI cross-platform.
        static let standard = CGFloat(0.5)
    }

    // MARK: - Motion
    /// Animations et durées. À utiliser plutôt que des Animation.easeInOut(duration: x) ad-hoc.
    enum Motion {
        /// 0.2s easeInOut — toggle disclosure (thinking, tool calls).
        static let standard = Animation.easeInOut(duration: 0.2)
    }

    // MARK: - Layout
    /// Contraintes de layout (largeurs max, hauteurs minimales, insets de panel).
    enum Layout {
        /// 720pt — largeur max de la liste de routines sur panel large (centrée).
        /// Sur panel standard (680pt) on reste full-width.
        static let maxWidthRoutines = CGFloat(720)

        /// 32pt — hauteur minimale d'une row dense en mode task-report.
        /// Densité Reminders.app / Things 3 (≈32pt). On sacrifie la cible HIG
        /// 44pt parce que les contrôles internes (StatusPill toggle) ont leur
        /// propre hit-area et que le row entier est tappable. La densité prime.
        static let rowMinHeight = CGFloat(32)

        /// 42pt — inset horizontal de tous les panels (Settings/Brain/History/Chat)
        /// dans NotchView. Cette valeur est *aussi* utilisée en négatif (-42)
        /// dans ScrollEdgeFade.swift pour permettre aux carousels edge-to-edge
        /// de dépasser. Garder ces deux call-sites en synchronisation.
        static let panelHorizontalInset = CGFloat(42)

        /// 14pt — top inset des panels structurés (Settings/Brain/History).
        static let panelTopInset = CGFloat(14)

        /// 25pt — bottom inset des panels structurés. Plus large que le top
        /// pour laisser respirer + accommoder le fade `FadingScrollView`.
        static let panelBottomInset = CGFloat(25)

        /// 4pt — top inset variant ChatView. Moins épais que les panels structurés
        /// parce que les premiers messages doivent monter plus haut.
        static let chatTopInset = CGFloat(4)

        /// 18pt — bottom inset variant ChatView. Espace pour l'input bar fixée
        /// en bas (qui a son propre padding interne).
        static let chatBottomInset = CGFloat(18)

        /// Alias historique de `rowMinHeight` (32pt). Conservé pour compatibilité ;
        /// sera retiré une fois les call-sites migrés.
        static let routineRowMinHeight = CGFloat(32)
        /// Alias historique remplacé par `DS.Padding.rowH` (14pt).
        /// Conservé pour compatibilité ; sera retiré une fois les call-sites migrés.
        static let routineRowPadH = CGFloat(14)
    }
}
