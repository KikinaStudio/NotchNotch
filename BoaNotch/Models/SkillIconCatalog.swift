import Foundation

/// Per-skill SF Symbol mapping for the Tools tab carousels in `BrainView`.
///
/// Keys are `SkillInfo.id` (`"<category>/<name>"`). Values are SF Symbol
/// names available in macOS 14+ (SF Symbols 5). Outline by default; `.fill`
/// only when the outline variant doesn't exist at the 22pt card size or
/// would read as illegible. Such exceptions carry an inline comment.
///
/// Lookup is via `icon(for:)`, which falls back to a category-level icon
/// when a skill is missing — so adding a new Hermes skill never breaks
/// the grid; the worst case is a category-shared glyph until the dict
/// is updated.
enum SkillIconCatalog {

    static let icons: [String: String] = [

        // MARK: apple
        "apple/apple-notes": "note.text",
        "apple/apple-reminders": "checklist",
        "apple/findmy": "location",
        "apple/imessage": "message",

        // MARK: autonomous-ai-agents — each agent gets a glyph hinting its
        // surface area, not the generic brain (which the category prefix
        // already carries).
        "autonomous-ai-agents/claude-code": "chevron.left.forwardslash.chevron.right",
        "autonomous-ai-agents/codex": "terminal",
        "autonomous-ai-agents/hermes-agent": "cube.transparent",
        "autonomous-ai-agents/opencode": "curlybraces",

        // MARK: creative
        "creative/architecture-diagram": "square.on.square.dashed",
        "creative/ascii-art": "textformat.abc",
        "creative/ascii-video": "play.rectangle",
        "creative/baoyu-comic": "book",
        "creative/baoyu-infographic": "chart.bar.doc.horizontal",
        "creative/claude-design": "pencil.and.ruler",
        "creative/comfyui": "point.3.connected.trianglepath.dotted",
        "creative/creative-ideation": "lightbulb",
        "creative/design-md": "doc.richtext",
        "creative/excalidraw": "scribble.variable",
        "creative/humanizer": "person.wave.2",
        "creative/manim-video": "function",
        "creative/p5js": "paintpalette",
        "creative/pixel-art": "square.grid.3x3",
        "creative/popular-web-designs": "safari",
        "creative/pretext": "text.book.closed",
        "creative/sketch": "pencil.tip",
        "creative/songwriting-and-ai-music": "music.quarternote.3",
        "creative/touchdesigner-mcp": "waveform.path",

        // MARK: data-science
        "data-science/jupyter-live-kernel": "chart.line.uptrend.xyaxis",

        // MARK: devops
        "devops/google-oauth-read-only": "key",
        "devops/kanban-orchestrator": "rectangle.split.3x1",
        "devops/kanban-worker": "hammer",
        "devops/webhook-subscriptions": "link",

        // MARK: dogfood
        "dogfood": "pawprint",
        "dogfood/hermes-agent-setup": "gearshape.2",

        // MARK: email
        "email/himalaya": "envelope",

        // MARK: gaming
        "gaming/minecraft-modpack-server": "cube",
        "gaming/pokemon-player": "gamecontroller",

        // MARK: github
        "github/codebase-inspection": "magnifyingglass",
        "github/github-auth": "person.badge.key",
        "github/github-code-review": "eye",
        "github/github-issues": "exclamationmark.bubble",
        "github/github-pr-workflow": "arrow.triangle.pull",
        "github/github-repo-management": "folder.badge.gearshape",

        // MARK: inference-sh
        "inference-sh/cli": "command",

        // MARK: leisure
        "leisure/find-nearby": "mappin.and.ellipse",

        // MARK: mcp
        "mcp/mcporter": "shippingbox",
        "mcp/native-mcp": "puzzlepiece.extension",

        // MARK: media
        "media/gif-search": "photo.stack",
        "media/heartmula": "heart.text.square",
        "media/songsee": "music.note.list",
        "media/spotify": "headphones",
        "media/youtube-content": "play.rectangle.on.rectangle",

        // MARK: mlops/cloud
        "mlops/cloud/lambda-labs": "cloud",
        "mlops/cloud/modal": "cloud.bolt",

        // MARK: mlops/evaluation
        "mlops/evaluation/huggingface-tokenizers": "textformat",
        "mlops/evaluation/lm-evaluation-harness": "checkmark.seal",
        "mlops/evaluation/nemo-curator": "tray.and.arrow.down",
        "mlops/evaluation/saelens": "scope",
        "mlops/evaluation/weights-and-biases": "chart.xyaxis.line",

        // MARK: mlops top-level
        "mlops/huggingface-hub": "face.smiling", // proxy for HF mascot; outline-only set has no logo
        "mlops/research/dspy": "doc.text.magnifyingglass",

        // MARK: mlops/inference
        "mlops/inference/gguf": "shippingbox.and.arrow.backward",
        "mlops/inference/guidance": "arrow.triangle.branch",
        "mlops/inference/instructor": "list.bullet.rectangle",
        "mlops/inference/llama-cpp": "memorychip",
        "mlops/inference/obliteratus": "scissors",
        "mlops/inference/outlines": "rectangle.dashed",
        "mlops/inference/tensorrt-llm": "bolt.horizontal",
        "mlops/inference/vllm": "bolt",

        // MARK: mlops/models
        "mlops/models/audiocraft": "waveform",
        "mlops/models/clip": "photo.on.rectangle",
        "mlops/models/llava": "eye.trianglebadge.exclamationmark",
        "mlops/models/segment-anything": "lasso",
        "mlops/models/stable-diffusion": "wand.and.stars",
        "mlops/models/whisper": "mic",

        // MARK: mlops/training
        "mlops/training/accelerate": "gauge.with.dots.needle.67percent",
        "mlops/training/axolotl": "tortoise",
        "mlops/training/flash-attention": "bolt.square",
        "mlops/training/grpo-rl-training": "arrow.triangle.2.circlepath",
        "mlops/training/hermes-atropos-environments": "globe.americas",
        "mlops/training/peft": "slider.horizontal.3",
        "mlops/training/pytorch-fsdp": "rectangle.split.2x2",
        "mlops/training/pytorch-lightning": "bolt.fill", // outline lightning isn't visually a bolt at 22pt
        "mlops/training/simpo": "scalemass",
        "mlops/training/slime": "drop",
        "mlops/training/torchtitan": "flame",
        "mlops/training/trl-fine-tuning": "dial.medium",
        "mlops/training/unsloth": "hare",

        // MARK: mlops/vector-databases
        "mlops/vector-databases/chroma": "circle.hexagongrid",
        "mlops/vector-databases/faiss": "square.stack.3d.up",
        "mlops/vector-databases/pinecone": "leaf",
        "mlops/vector-databases/qdrant": "cube.box",

        // MARK: note-taking
        "note-taking/obsidian": "diamond",

        // MARK: productivity
        "productivity/airtable": "tablecells",
        "productivity/google-workspace": "tray.full",
        "productivity/kikinaor-missions": "flag",
        "productivity/linear": "arrow.up.right",
        "productivity/maps": "map",
        "productivity/nano-pdf": "doc.text",
        "productivity/notion": "square.text.square",
        "productivity/ocr-and-documents": "doc.viewfinder",
        "productivity/powerpoint": "rectangle.on.rectangle.angled",
        "productivity/review-design-assets-via-email": "envelope.open",

        // MARK: red-teaming
        "red-teaming/godmode": "shield.lefthalf.filled", // outline shield reads as a generic icon; lefthalf signals red-teaming intent

        // MARK: research
        "research/arxiv": "books.vertical",
        "research/blogwatcher": "newspaper",
        "research/domain-intel": "globe",
        "research/duckduckgo-search": "magnifyingglass.circle",
        "research/llm-wiki": "brain.head.profile",
        "research/ml-paper-writing": "pencil.and.list.clipboard",
        "research/polymarket": "chart.pie",
        "research/research-paper-writing": "doc.append",
        "research/wiki-cron-ingest": "arrow.down.doc",

        // MARK: smart-home
        "smart-home/openhue": "lightbulb.led",

        // MARK: social-media
        "social-media/xitter": "bird",
        "social-media/xurl": "link.badge.plus",

        // MARK: software-development
        "software-development/code-review": "checkmark.rectangle.stack",
        "software-development/debugging-hermes-tui-commands": "ant",
        "software-development/hermes-agent-skill-authoring": "square.and.pencil",
        "software-development/node-inspect-debugger": "ladybug",
        "software-development/plan": "list.bullet.clipboard",
        "software-development/python-debugpy": "ant.circle",
        "software-development/requesting-code-review": "person.2.badge.gearshape",
        "software-development/spike": "bolt.ring.closed",
        "software-development/subagent-driven-development": "person.3.sequence",
        "software-development/systematic-debugging": "stethoscope",
        "software-development/test-driven-development": "checkmark.shield",
        "software-development/writing-plans": "doc.text.below.ecg",

        // MARK: yuanbao
        "yuanbao": "circle.dashed"
    ]

    /// Resolves the SF Symbol for a skill. Falls back to the supplied
    /// category icon when the skill isn't mapped — keeps the grid working
    /// when Hermes ships a new skill before this catalog is updated.
    static func icon(for skill: SkillInfo, fallback: (String) -> String) -> String {
        if let mapped = icons[skill.id] {
            return mapped
        }
        return fallback(skill.category)
    }
}
