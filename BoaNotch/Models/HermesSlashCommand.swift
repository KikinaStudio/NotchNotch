import Foundation

/// A Hermes slash command typed in the chat. No HTTP route of the gateway runs them (checked up
/// to v0.22.2): sent as text, the model improvises ("/new" answered "Nouvelle session prête" with
/// nothing reset) or acts on it ("/loop 5m ping" created a real cron). Like Hermes Desktop,
/// `ChatViewModel` never sends one to the model: the few with a NotchNotch equivalent run it, the
/// others get a notice. Exact name match, as Hermes's `resolve_command`, plus a suggestion for a
/// near miss ("/models" → "/model"): a path ("/Users/…/rapport.pdf"), a word far from every
/// command ("/bonjour") or a skill ("/llm-wiki …") isn't matched and still goes out.
enum HermesSlashCommand: Equatable {
    case newConversation
    case modelMenu
    case history
    case stop
    /// Hermes-only command, with the name as typed (lowercased) for the notice.
    case unavailable(String)
    /// Typo of a command (`typed` as typed, lowercased), never sent: the notice suggests the command.
    case nearMiss(typed: String, suggestion: String)

    /// The command `text` starts with, or nil when its first word isn't one of Hermes's.
    static func match(_ text: String) -> HermesSlashCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let word = trimmed.dropFirst().prefix { !$0.isWhitespace }.lowercased()
        // "/new." or "/model;" are still the command.
        var name = word
        while name.last?.isPunctuation == true { name.removeLast() }
        guard registry.contains(name) else {
            return closestCommand(to: name).map { .nearMiss(typed: "/" + word, suggestion: "/" + $0) }
        }
        return runnable.first { $0.name == name || $0.aliases.contains(name) }?.command ?? .unavailable("/" + name)
    }

    /// The commands NotchNotch runs, with the French line of the `/` palette (`SlashPalette`).
    static let runnable: [(command: HermesSlashCommand, name: String, aliases: [String], description: String)] = [
        (.newConversation, "new", ["reset", "clear"], "Commence une nouvelle conversation"),
        (.modelMenu, "model", [], "Choisis le modèle de cette conversation"),
        (.history, "sessions", ["resume"], "Ouvre l'historique pour reprendre une conversation"),
        (.stop, "stop", [], "Arrête la réponse en cours"),
    ]

    /// Line shown above the composer when NotchNotch doesn't run the command; nil otherwise.
    var notice: String? {
        switch self {
        case .unavailable(let name):
            return "\(name) est une commande de Hermes qui ne marche pas ici. Écris ta demande avec tes mots, ou utilise /new, /model, /sessions ou /stop."
        case .nearMiss(let typed, let suggestion):
            return "\(typed) n'est pas une commande. Tu voulais dire \(suggestion) ? Rien n'a été envoyé."
        default:
            return nil
        }
    }

    /// The command `name` looks like a typo of: one edit away (letter added, missing, changed or
    /// swapped: "models", "mdoel", "loops") or the start of a command name ("sess"), as Hermes
    /// expands prefixes. Words of 3+ characters starting with a letter, no path. Closest first,
    /// then shortest; names under 3 characters (`q`, `s`, `bg`…) are never suggested.
    private static func closestCommand(to name: String) -> String? {
        guard name.count >= 3, name.first?.isLetter == true, !name.contains("/") else { return nil }
        return registry
            .filter { $0.count >= 3 }
            .map { (command: $0, distance: editDistance(name, $0)) }
            .filter { $0.distance <= 1 || $0.command.hasPrefix(name) }
            .min { ($0.distance, $0.command.count, $0.command) < ($1.distance, $1.command.count, $1.command) }?
            .command
    }

    /// Edits to turn `a` into `b`, a swap of two neighbours counting as one ("mdoel" → "model").
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }

    /// Names and aliases of `COMMAND_REGISTRY` (`hermes_cli/commands.py`, v0.22.2, plus
    /// `initiate-setup` from 0.21.x). Refresh it when Hermes adds commands: a missing one goes to
    /// the model as text, as before H5.
    static let registry: Set<String> = [
        "agents", "approvals", "approve", "battery", "bg", "blueprint", "bp", "branch", "browser",
        "btw", "bundles", "busy", "clear", "codex-runtime", "codex_runtime", "commands", "compact",
        "compose", "compress", "config", "context", "copy", "cron", "ctx", "curator", "debug",
        "deny", "diff", "egress", "exit", "export", "fast", "focus", "footer", "fork", "gateway",
        "generate-pet", "goal", "handoff", "hatch", "hb", "heartbeat", "help", "history", "image",
        "import", "indicator", "init", "initiate-setup", "initiate_setup", "insights", "journey",
        "kanban", "learn", "learning", "login", "loop", "memory", "memory-graph", "moa", "model",
        "new", "palette", "paste", "pause", "personality", "pet", "plan", "platform", "platforms",
        "plugins", "proactive", "profile", "prompt", "q", "queue", "quit", "reasoning", "redraw",
        "refine", "reload", "reload-mcp", "reload-skills", "reload_mcp", "reload_skills", "reset",
        "restart", "resume", "retry", "review", "rollback", "s", "save", "sb", "sessions",
        "set-home", "sethome", "skills", "skin", "snap", "snapshot", "start", "status",
        "statusbar", "steer", "stop", "subgoal", "subscription", "suggest", "suggestions", "tasks",
        "timestamps", "title", "tools", "toolsets", "topic", "topup", "ts", "undo", "update",
        "upgrade", "usage", "v", "verbose", "version", "voice", "wake", "whoami", "worktree",
        "yolo",
    ]
}
