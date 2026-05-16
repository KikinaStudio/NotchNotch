# notchnotch v1.4.0

## Plus jamais de Terminal pour démarrer Hermes

Jusqu'à v1.3.2, après l'install Hermes ne démarrait que si tu lançais `hermes gateway run` à la main dans Terminal — et fallait le garder ouvert. Pour un utilisateur non-tech c'était un dealbreaker : il envoyait son premier message dans le chat, voyait *"Hermes ne répond pas..."*, et n'avait aucune indication de quoi faire.

v1.4.0 corrige ça avec un **LaunchAgent macOS** installé automatiquement.

### Ce qui change concrètement

- **Onboarding** : à la fin de l'étape *"Setting up your AI agent"*, NotchNotch installe maintenant un LaunchAgent (`~/Library/LaunchAgents/ai.hermes.gateway.plist`) qui démarre Hermes au login et le relance s'il crashe. Tu peux fermer ton Mac, le rouvrir le lendemain — Hermes est déjà là quand tu envoies un message.

- **Toast réparable** : si jamais Hermes ne répond pas (process tué à la main, plist supprimée, etc.), le toast *"Hermes ne répond pas. Tape pour réparer."* est maintenant **cliquable**. Un tap installe/relance le LaunchAgent, attend que `/health` réponde, et rejoue ton message. Plus besoin d'ouvrir Terminal.

- **Réglages → Hermes** : nouvelle section qui montre l'état du LaunchAgent (actif / en pause / pas installé), avec boutons *Installer*, *Redémarrer*, *Désinstaller*, et *Voir les logs* (qui révèle `~/.hermes/logs/gateway.log` dans Finder).

- **Au démarrage** : si le plist existe mais que launchd ne l'a pas chargé (mise à jour de NotchNotch, edit manuel), l'app le re-charge automatiquement sans rien demander.

### Sous le capot

Le LaunchAgent utilise le label `ai.hermes.gateway` (convention communauté Hermes), tourne `python3 hermes gateway run --replace`, et garde des logs séparés stdout/stderr dans `~/.hermes/logs/`. Le flag `--replace` évite les conflits de port si une instance manuelle tourne déjà — le LaunchAgent reprend la main proprement.

User-scoped (`~/Library/LaunchAgents/`), donc zéro sudo, zéro mot de passe admin, zéro TCC à accorder. Tu peux toujours le contrôler avec `launchctl bootout/bootstrap gui/$(id -u)/ai.hermes.gateway` si tu veux faire du custom.

## API HTTP toujours active

Hermes n'ouvre le port 8642 que si `API_SERVER_ENABLED=true` est dans `~/.hermes/.env`. Avant v1.4.0 ce flag était implicite quand un messaging platform était configuré, mais pour un user qui n'a ni Telegram, ni Discord, ni Slack, Hermes tournait en mode **cron-only** — actif via le LaunchAgent, mais sans serveur HTTP que NotchNotch puisse joindre. Symptôme : toast jaune permanent *"Hermes ne répond pas"* même après une install propre.

v1.4.0 écrit `API_SERVER_ENABLED=true` (et `API_SERVER_CORS_ORIGINS=*` pour l'extension Clipper) automatiquement à la fin de l'onboarding. Sur les installs existantes (upgrade depuis v1.3.x via Sparkle), le boot probe NotchNotch vérifie ces deux clés au lancement et les ajoute si absentes — puis kickstart le LaunchAgent pour que Hermes les relise. Toute valeur que tu aurais explicitement posée (`API_SERVER_ENABLED=false` par exemple) est respectée et n'est pas écrasée.

## Modèles OpenRouter gratuits à jour

La liste des modèles OpenRouter `:free` proposés dans le picker est maintenant **fetch live** depuis l'API OpenRouter au premier lancement, mise en cache 24h dans UserDefaults, et rafraîchie une fois par jour. Plus de liste rancie qui se traîne pendant des mois pendant qu'OpenRouter retire des modèles — au moindre `hermes-3-405b:free` qui disparaît côté serveur, le picker NotchNotch est à jour au prochain refresh.

Fallback réseau-down : si OpenRouter est injoignable au tout premier lancement, le picker affiche une liste hardcodée de 4 modèles `:free` connus comme stables (DeepSeek V4 Flash, Nemotron 3 Nano Omni, Gemma 4 26B / 31B). Les rafraîchissements suivants tenteront de nouveau silencieusement.

## `max_tokens` adapté aux modèles gratuits

Le tier gratuit d'OpenRouter rejette toute requête où `max_tokens` excède ~13K (plancher de crédits par requête). Hermes calcule `max_tokens` à partir de `context_length` par défaut, ce qui balloon à 65K+ sur des modèles modernes — et chaque chat se fait shooter en HTTP 402 *"You requested up to 65536 tokens, but can only afford 13333"*.

v1.4.0 cap explicitement `model.max_tokens` à **8000** dans `~/.hermes/config.yaml` dès qu'un modèle `:free` est sélectionné dans le picker (marge confortable sous le plancher). Si tu reviens sur un modèle payant, l'override est retiré et Hermes reprend son calcul naturel à partir du context_length. Les users qui upgradent depuis pre-v1.4.0 et qui étaient déjà sur un `:free` se voient appliquer la cap au prochain boot (uniquement si `max_tokens` n'est pas déjà posé manuellement — un override explicite est respecté).

## Pour mettre à jour

Sparkle te proposera v1.4.0 automatiquement. À la première ouverture après update, NotchNotch détecte qu'il n'y a pas encore de LaunchAgent et tu auras une option *Installer* dans Réglages → Hermes (ou ça s'installera tout seul au premier toast "Hermes ne répond pas" cliquable).

### Le reste

Tout le contenu de v1.3.x reste : Contrôle du Mac (opt-in), trois onglets Memory/Tools/Missions, timeline unifiée du chat, Liquid Glass, SF Symbols 7, Hermes 0.13 (SSE retry, FR locale, fix MiniMax), refine wand sur routines locales, toasts par couleur sémantique, empty-state carousel, 11 providers LLM, sélecteur de memory provider.

Bypass Gatekeeper au premier launch (right-click → Open → Open) — notchnotch n'est pas notarized par Apple.
