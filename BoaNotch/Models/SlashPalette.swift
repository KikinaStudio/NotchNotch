import Foundation

/// One row of the composer's `/` palette.
struct SlashSuggestion: Identifiable, Equatable {
    enum Kind { case command, skill, hermesOnly }

    /// Without the slash, as inserted: `sessions`, `reset`, `llm-wiki`, `loop`.
    let name: String
    let description: String
    let kind: Kind

    var id: String { "\(kind):\(name)" }
    /// A Hermes-only command is shown greyed out: ↑ ↓ skip it, a click does nothing.
    var isSelectable: Bool { kind != .hermesOnly }
}

/// What the composer's `/` palette suggests, like Hermes Desktop's popover and Claude Code's:
/// the commands NotchNotch runs first (French descriptions), then the installed skills (their
/// `SKILL.md` description), then a greyed Hermes-only command, only once its full name is
/// typed (`/loop`) so it's flagged before Enter. Aliases (`/reset`, `/resume`) show only when
/// typed. A match on the start of a name comes before a match inside it (`/wiki` → `llm-wiki`).
enum SlashPalette {
    /// The word typed after "/", lowercased, or nil when the palette is closed: the draft must
    /// start with "/" and still be on its first word, with no second "/" (a path such as
    /// `/Users/leon/…` closes it, as in Desktop).
    static func query(for draft: String) -> String? {
        guard draft.hasPrefix("/") else { return nil }
        let word = draft.dropFirst()
        guard !word.contains(where: { $0.isWhitespace || $0 == "/" }) else { return nil }
        return word.lowercased()
    }

    static func suggestions(for query: String, skills: [SkillInfo]) -> [SlashSuggestion] {
        /// 0 = the name starts with the query, 1 = contains it (2 letters or more: one letter
        /// would match half the skills), nil = no match.
        func rank(_ name: String) -> Int? {
            if query.isEmpty || name.hasPrefix(query) { return 0 }
            return query.count >= 2 && name.contains(query) ? 1 : nil
        }

        var commands: [(rank: Int, item: SlashSuggestion)] = []
        for entry in HermesSlashCommand.runnable {
            if let r = rank(entry.name) {
                commands.append((r, SlashSuggestion(name: entry.name, description: entry.description, kind: .command)))
            } else if !query.isEmpty, let alias = entry.aliases.first(where: { $0.hasPrefix(query) }) {
                let description = "\(entry.description) (comme /\(entry.name))"
                commands.append((0, SlashSuggestion(name: alias, description: description, kind: .command)))
            }
        }

        let skillRows = commandSkills(skills)
            .compactMap { skill in rank(skill.slug).map { (rank: $0, skill: skill) } }
            .sorted { ($0.rank, $0.skill.slug) < ($1.rank, $1.skill.slug) }
            .map { SlashSuggestion(name: $0.skill.slug, description: $0.skill.description, kind: .skill) }

        var items = commands.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .map(\.element.item)
        items += skillRows
        // Not for one-letter aliases (`/s`, `/q`, `/v`): every name typed starts with one.
        let isRunnable = HermesSlashCommand.runnable.contains { $0.name == query || $0.aliases.contains(query) }
        if query.count >= 2, HermesSlashCommand.registry.contains(query), !isRunnable {
            items.append(SlashSuggestion(name: query, description: HermesSlashCommand.paletteHint(for: query), kind: .hermesOnly))
        }
        return items
    }

    /// The installed skill `text` starts with (`/llm-wiki range ça` → llm-wiki), as Hermes reads
    /// it on Telegram and in its terminal. Its API takes the line as plain text, so
    /// `ChatViewModel` adds a system line asking the agent to load the skill.
    static func invokedSkill(in text: String, skills: [SkillInfo]) -> (slug: String, name: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let word = trimmed.dropFirst().prefix { !$0.isWhitespace }.lowercased()
        return commandSkills(skills).first { $0.slug == word }.map { ($0.slug, $0.name) }
    }

    /// Skills that get a `/command`, as Hermes's `scan_skill_commands`: slug of the frontmatter
    /// `name`, first one wins on a duplicate, none that collides with a Hermes command (Hermes
    /// skips those too: `/plan` stays the command).
    private static func commandSkills(_ skills: [SkillInfo]) -> [(slug: String, name: String, description: String)] {
        var seen = Set<String>()
        return skills.compactMap { skill in
            let slug = slugify(skill.name)
            guard !slug.isEmpty, !HermesSlashCommand.registry.contains(slug), seen.insert(slug).inserted else { return nil }
            return (slug, skill.name, cleanDescription(skill.description, name: skill.name))
        }
    }

    /// `slugify_skill_name` in `agent/skill_commands.py`: "Foo Bar" → "foo-bar".
    private static func slugify(_ name: String) -> String {
        let lowered = name.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
        let kept = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
        var slug = String(String.UnicodeScalarView(kept))
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// `BrainViewModel` keeps YAML quotes (`"GitHub auth setup…"`) and block markers (`>`).
    private static func cleanDescription(_ raw: String, name: String) -> String {
        let text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return ["", ">", ">-", "|", "|-"].contains(text) ? "Utilise le skill \(name)" : text
    }
}
