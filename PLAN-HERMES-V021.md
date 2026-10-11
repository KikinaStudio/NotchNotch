# NotchNotch x Hermes v0.21 : mises à jour et features

Suivi du plan lancé le 2026-10-11 après le probe H0. Détail technique de chaque point : section « Probe Hermes v0.21.6 (2026-10-11) » de `sse-probe-notes.md` (colonne `#` = numéro de probe).

Statuts : ✅ fait · 🔜 prochaine · ⏳ à faire · ⏸ bloqué / décision · ❌ abandonné

## Sessions

| Session | Sujet | Probe | Statut | Commit |
|---|---|---|---|---|
| H0 | Probe de compatibilité v0.21.6 (lecture seule) | 1–14 | ✅ | `d9a2251` |
| H1 | `API_SERVER_KEY` : Bearer sur les 6 appels, création de la clé (boot, onboarding, réparation), 401 → réparation sans rotation | 1, 8 | ✅ | `19372e3` |
| H1b | LaunchAgent : ne plus écrire le plist, déléguer à `hermes gateway start/restart/uninstall` | hors probe | ✅ fusionné dans H1 | `19372e3` |
| H2a | Identité de session : `X-Hermes-Session-Id` ignoré sur `/v1/responses` → un seul `notchnotch-<uuid>` par conversation, envoyé en `conversation` + `X-Hermes-Session-Key` et lu dans `sessions.session_key` ; `TitleStore`, session active de l'historique, reprise d'une conversation | 2 | ✅ | |
| H2b | Flux SSE : événement `hermes.status`, erreurs fournisseur reçues en `response.completed` (402 affiché comme une réponse), `parseOutput` qui perd `summary[].text`, nouveaux outils dans `verbMapping` (`tool_search`, `tool_describe`, `cronjob_manage`) | 2, 3 | ✅ | |
| H3a | Transport du chat sur `/v1/chat/completions` (stream) quand `/health` renvoie `version`, sinon `/v1/responses` inchangé ; `/v1/runs` écarté (pas de raisonnement en direct ni de `hermes.status`). Vrai statut d'échec (`finish_reason: "error"`) | 4 | ✅ | `86f71ac` |
| H3b | Carte d'approbation dans la bulle (`approval.request` → « Autoriser » `once` / « Refuser » `deny` → `POST /v1/runs/{id}/approval`), toast si le notch est fermé, expiration | 4 | ✅ | |
| H4 | Modèle par requête (`model` + `provider` dans le corps) et liste depuis `GET /api/model/options` | 5 | ⏳ | |
| H5 | Commandes slash : `/goal` non débloqué en HTTP ; risque qu'un `/loop` tapé crée des crons | 6 | ⏸ `/goal` attend Hermes (ou H6) | |
| H6 | Branchement RPC WebSocket `hermes dashboard` (`slash.exec`). Le raisonnement et les approbations n'en dépendent plus (H3) : il ne reste que `/goal` | 7 | ⏸ décision (question ouverte 4) | |
| H7 | Routines : toasts d'échec via `latest_execution.error`, `## Error` dans les sorties | 8 | ⏳ | |
| H8 | `state.db` : coût affiché « 0 $ » au lieu de « — » quand le coût estimé est à 0 | 9 | ⏳ | |
| H9 | Sélecteur de mémoire : Hindsight déplacé dans `~/.hermes/plugins/`, scan à corriger | 10 | ⏳ | |
| H10 | Routage fournisseurs : écrire sous `provider_routing.models.<id>` ; pas de ZDR | 11 | ⏳ | |
| H11 | Secrets dans le Trousseau (`secrets.command`) | 12 | ⏳ optionnel | |
| H12 | Code mort : `probeCompressionEndpoint` (`compression.summary_base_url` n'existe plus) | 13 | ⏳ | |
| H13 | Contrôle du Mac : `hermes computer-use permissions status --json` remplace l'« acte de foi » | 14 | ⏳ | |
| Clipper | Envoyer `API_SERVER_KEY` depuis l'extension (en 401 depuis H1) | 1 | ⏳ | |

## Petits correctifs hors sessions

- ⏳ Onboarding : `hermes init` n'existe plus (`OnboardingViewModel.swift`, erreur avalée par `try?`).
- ⏳ `~/.hermes/.env` contient 8 lignes `OPENROUTER_API_KEY=` : origine inconnue (pas `writeRawEnv`, qui remplace toutes les occurrences).
- ⏳ Remplacer `/Applications/notchnotch.app` par une build à jour : l'ancienne relance au login et casse le chat en 401.
- ⏸ Modèle par défaut MiniMax en 402 (crédit épuisé) : toutes les routines échouent. Décision de Jérémie : recharger ou changer de modèle.
- ⏳ `generateTitle` fait doublon avec les titres Hermes : v0.21.6+ titre lui-même chaque session, `/v1/responses` compris (`title_source = llm`). À garder pour les vieux gateways.

## Questions ouvertes (du probe)

1. ~~`/v1/runs` : comment se fait la continuité de conversation ?~~ → la continuité par clé y marche, mais ce transport est abandonné (H3) : le chat passe sur `/v1/chat/completions`, qui suit `X-Hermes-Session-Id`.
2. `memory.write_approval: true` sur `api_server` : bloqué comme « sans surveillance » ?
3. Rester sur `main` ou repasser sur la stable quand v0.21.7 sortira ?
4. Hermes Desktop : compléter, s'y brancher (H6) ou s'en démarquer ?
5. ~~Clé API : `.env` ou Trousseau ?~~ → `.env` en H1, Trousseau reporté (H11).

## Journal

- **2026-10-11 — H0** : probe en lecture seule, Hermes passé en v0.21.6 (`main`), clé ajoutée à la main.
- **2026-10-11 — H1** : NotchNotch envoie la clé et la crée si absente ; NotchNotch n'écrit plus le plist du gateway. Testé : création de la clé au boot, 401 → réparation sans rotation, `.env` en 0600, plist intact, clé absente des logs. Ajouté au passage : toasts actionnables 8 s au lieu de 3 s. Non testé : onboarding sur une install neuve, génération du titre.
- **2026-10-11 — H2a** : un seul `notchnotch-<uuid>` par conversation, envoyé en `conversation`, `X-Hermes-Session-Id` (vieux gateways) et `X-Hermes-Session-Key` (seulement avec le Bearer : 403 sans `API_SERVER_KEY`). L'historique lit la clé dans `sessions.session_key` (repli sur l'ID de ligne) ; la reprise remet la clé en `conversation`. Option « lire l'en-tête de réponse » écartée : en SSE il part avant l'exécution, donc rate une rotation par compression, et la reprise demandait une table session → conversation. Vérifié au curl : l'en-tête renvoie l'ID réel (SSE et JSON), la clé est écrite au 1er tour, une clé réutilisée retombe sur la ligne précédente (d'où une clé par conversation), et la reprise après une autre conversation retrouve le contexte (même ligne). Héritage de la clé par les lignes enfants de compression : lu dans le code (`_INHERIT_PARENT_ROUTING_SQL`), pas déclenché. Mémoire : Hindsight et `MEMORY.md`/`USER.md` n'utilisent pas la clé. Non testé dans l'UI (panneau du notch non pilotable) : titre, surbrillance et reprise à vérifier à la main. Lignes de probe `notchnotch-h2a-*` laissées dans `state.db`.
- **2026-10-11 — H2b** : `hermes.status` affiché comme ligne d'état éphémère dans la bulle en cours (dernier statut reçu, effacé dès que le tour avance : texte, raisonnement, outil, retry), sans toast ; tout kind est traité pareil. Erreur fournisseur : option (a), rien de plus. Pas d'heuristique (usage à 0 et `lifecycle` arrivent aussi sur un tour normal) ; le vrai statut d'échec viendra avec H3a. `parseOutput` lit `summary[].text` et concatène les blocs ; `sendResponse` supprimé (aucun appelant). `verbMapping` aligné sur les noms enregistrés dans `tools/` ; `tool_call` est remplacé par le vrai outil (`calls[0]`, `×N` si lot) dans `HermesClient.toolDisplay`, ce qui masque aussi une commande `terminal` passée par le pont. Tous les `print` de `HermesClient` passent en `os_log`. Vérifié au curl (clé, `store: false`) : 402 MiniMax = `response.completed` sans `error`, usage à 0, précédé d'un `warn` (titre auxiliaire) et d'un `lifecycle` ❌ ; l'item `reasoning` porte `summary` sans `text`, en SSE comme en JSON. Build OK ; `toolDisplay` auto-vérifié sur 8 cas (code extrait, script non commité). Constat : en 402, la ligne ❌ est aussitôt remplacée par le texte de facturation, qui s'explique seul. Hermes titre lui-même les sessions `/v1/responses` depuis v0.21.6 (`f726090`) : CLAUDE.md corrigé. Testé dans l'UI par Jérémie (l'app n'est pas pilotable par computer-use) : raisonnement, verbes (recherche web, lecture de fichier) et 402 OK.
- **2026-10-11 — H3 (H3a + H3b)** : `/v1/runs` écarté après lecture du code (`_execute_run` sans `reasoning_callback` ni `status_callback` ; son `reasoning.available` est le texte tronqué à 500 caractères). Le chat passe sur `/v1/chat/completions` (stream) quand `/health` renvoie `version` (v0.21.6+), sinon `/v1/responses` inchangé (relu, intact : seuls l'envoi et le routage `<think>` sont factorisés dans `openStream` / `routeText` / `flushText`). `X-Hermes-Session-Id` = ligne la plus récente dont `session_key` = la clé (`SessionStore.latestRowId`), sinon la clé. Mêmes `StreamEvent`, même retry. `finish_reason: "error"` → `HermesError.agentFailed` (message de Hermes tel quel, texte générique si absent) ; `length` = réponse normale. Pas d'aperçu d'outil pour le pont `tool_call` (son `label` décrit l'outil enveloppé, peut-être une commande). Approbations : carte dans la bulle, « Autoriser » (`once`) / « Refuser » (`deny`) selon `choices`, jamais `always` ; 409 → « expirée et refusée » ; du texte sous une carte sans réponse = délai dépassé ; toast `.info` actionnable si le notch est fermé. Nouvelle exception documentée dans `CLAUDE.md`. Vérifié au curl (section « Probe /v1/chat/completions (H3) » de `sse-probe-notes.md`) : continuité par ID, clé seule = session neuve, reprise H2a, 402, refus (dossier intact), 409, arrêt. Constat : un retry après coupure duplique le message utilisateur dans `state.db` (non contourné). Build OK, lint sans nouvelle alerte. Test dans l'UI par Jérémie : à faire.
