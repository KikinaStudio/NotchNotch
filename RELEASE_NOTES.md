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

### Pour mettre à jour

Sparkle te proposera v1.4.0 automatiquement. À la première ouverture après update, NotchNotch détecte qu'il n'y a pas encore de LaunchAgent et tu auras une option *Installer* dans Réglages → Hermes (ou ça s'installera tout seul au premier toast "Hermes ne répond pas" cliquable).

### Le reste

Tout le contenu de v1.3.x reste : Contrôle du Mac (opt-in), trois onglets Memory/Tools/Missions, timeline unifiée du chat, Liquid Glass, SF Symbols 7, Hermes 0.13 (SSE retry, FR locale, fix MiniMax), refine wand sur routines locales, toasts par couleur sémantique, empty-state carousel, 11 providers LLM, sélecteur de memory provider.

Bypass Gatekeeper au premier launch (right-click → Open → Open) — notchnotch n'est pas notarized par Apple.
