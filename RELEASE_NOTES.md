# notchnotch v1.3.0

## Nouveautés

- **Contrôle du Mac (opt-in).** Ton agent peut maintenant utiliser tes apps comme tu le ferais : ouvrir Mail et répondre à un thread, ranger des fichiers dans Finder, naviguer dans Safari. Discret (ton curseur ne bouge pas), sûr (jamais ton mot de passe ni `sudo`), et sous contrôle (mode d'approbation manuelle par défaut, smart ou off). L'onboarding propose la step en quatrième position, skippable à tout moment.
- **Trois onglets dans Brain : Memory · Tools · Missions.** L'ancien onglet Skills devient Tools, organisé en deux sections : une grille d'**Apps** connectées (Gmail, Drive, Spotify, Notion) et un catalogue de **Capacités** techniques avec recherche inline et bouton Parcourir pour installer depuis le Hermes Skills Hub. L'onglet Tasks devient Missions et héberge maintenant tes Routines (le panneau séparé a disparu).
- **Timeline unifiée du chat.** Réflexion de l'agent et appels d'outils s'affichent dans une chronologie ordonnée pendant le streaming, avec un récap "Réfléchi pendant Ns" une fois la réponse terminée. Chaque ligne peut être dépliée pour voir les arguments et le résultat.
- **Liquid Glass.** Sur macOS Tahoe (26+), le fond du panneau combine un dégradé noir-vers-verre avec la matière `.glassEffect` native. Camouflage propre du notch matériel, transparence subtile en bas. Fallback solide sur macOS 14/15.
- **SF Symbols 7.** Toutes les icônes du top bar redessinées avec l'effet `drawOn` au survol sur Tahoe. Burgers gauche (chat / search / new / history) et droite (settings / Memory / Tools / Missions) symétriques.

## Améliorations

- **Hermes 0.13.** Retry automatique sur déconnexions SSE (3 tentatives, backoff 1/2/4s, conversation préservée), interface en français (`display.language: fr`), fix MiniMax (endpoint `/anthropic` au lieu de `/v1`), scrubbing de secrets côté serveur, header `X-Hermes-Session-Key` pour la continuité de session.
- **Auto-update Sparkle stable.** Correction du `rpath @executable_path/../Frameworks` qui empêchait l'app de trouver Sparkle.framework après update. Le bypass Gatekeeper reste nécessaire à chaque mise à jour (notchnotch n'est pas notarized).
- **Refine sur les routines locales.** Quand une routine livre un résultat dans le notch, un bouton baguette apparaît à côté de Copy/Retry pour pré-remplir le composer avec un primer ("Pour cette routine, je voudrais que tu…") et l'envoyer en `system_context` à Hermes.
- **Toasts par couleur sémantique.** info (lavande), chat (bleu accent), success (vert pacman), error (corail), cron (ambre cloche). Le bleu n'est plus universel — il est réservé à la voix de l'agent.
- **Empty-state carousel du chat.** 26 prompts spécifiques à Hermes (Goals long-cours, mémoire, cron, Mail/agenda, web, shell, brain/wiki), shufflés au premier affichage, auto-rotation toutes les 2s avec chevrons gauche/droite.
- **Sélecteurs de fichiers visibles.** Les `NSOpenPanel` (paperclip, file picker des templates) flottent maintenant au-dessus du notch.
- **Catalogue de providers étendu.** Gemini, HuggingFace, Z.AI, Kimi-Coding, Xiaomi et Custom (endpoint OpenAI-compatible type Ollama/vLLM) s'ajoutent à Nous Portal / OpenRouter / OpenAI / Anthropic / MiniMax. Brand icons monochrome via Simple Icons.
- **Memory providers.** Sélecteur dans Settings pour basculer entre built-in, hindsight, mem0, supermemory, OpenViking, RetainDB. Local-only providers utilisables sans config supplémentaire ; les providers cloud demandent une clé API que NotchNotch écrit dans `~/.hermes/.env`.

## Pour mettre à jour

Si tu as déjà v1.2.1, notchnotch te proposera la mise à jour automatiquement au prochain lancement. Sinon, télécharge le DMG depuis [GitHub Releases](https://github.com/KikinaStudio/NotchNotch/releases/tag/v1.3.0).

**Important** : à chaque mise à jour, refais le bypass Gatekeeper au premier launch (right-click → Open → Open). C'est normal — notchnotch n'est pas (encore) notarized par Apple.
