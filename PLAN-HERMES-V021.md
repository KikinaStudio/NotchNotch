# NotchNotch x Hermes v0.21 : mises à jour et features

Suivi du plan lancé le 2026-10-11 après le probe H0. Détail technique de chaque point : section « Probe Hermes v0.21.6 (2026-10-11) » de `sse-probe-notes.md` (colonne `#` = numéro de probe).

Statuts : ✅ fait · 🔜 prochaine · ⏳ à faire · ⏸ bloqué / décision · ❌ abandonné

## Sessions

| Session | Sujet | Probe | Statut | Commit |
|---|---|---|---|---|
| H0 | Probe de compatibilité v0.21.6 (lecture seule) | 1–14 | ✅ | `d9a2251` |
| H1 | `API_SERVER_KEY` : Bearer sur les 6 appels, création de la clé (boot, onboarding, réparation), 401 → réparation sans rotation | 1, 8 | ✅ | `19372e3` |
| H1b | LaunchAgent : ne plus écrire le plist, déléguer à `hermes gateway start/restart/uninstall` | hors probe | ✅ fusionné dans H1 | `19372e3` |
| H2a | Identité de session : `X-Hermes-Session-Id` ignoré sur `/v1/responses` → lire l'ID renvoyé par le serveur ; `TitleStore`, session active de l'historique, reprise d'une conversation | 2 | 🔜 | |
| H2b | Flux SSE : événement `hermes.status`, erreurs fournisseur reçues en `response.completed` (402 affiché comme une réponse), `parseOutput` qui perd `summary[].text`, nouveaux outils dans `verbMapping` (`tool_search`, `tool_describe`, `cronjob_manage`) | 2, 3 | ⏳ | |
| H3a | Transport du chat sur `/v1/runs` + `/events` (préalable aux approbations) | 4 | ⏳ (question ouverte 1) | |
| H3b | Interface d'approbation (`approval.request` → choix → `POST /approval`) | 4 | ⏳ après H3a | |
| H4 | Modèle par requête (`model` + `provider` dans le corps) et liste depuis `GET /api/model/options` | 5 | ⏳ | |
| H5 | Commandes slash : `/goal` non débloqué en HTTP ; risque qu'un `/loop` tapé crée des crons | 6 | ⏸ `/goal` attend Hermes (ou H6) | |
| H6 | Branchement RPC WebSocket `hermes dashboard` (`slash.exec`, approbations natives) | 7 | ⏸ décision (question ouverte 4) | |
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

## Questions ouvertes (du probe)

1. `/v1/runs` : comment se fait la continuité de conversation ? Préalable à H3a.
2. `memory.write_approval: true` sur `api_server` : bloqué comme « sans surveillance » ?
3. Rester sur `main` ou repasser sur la stable quand v0.21.7 sortira ?
4. Hermes Desktop : compléter, s'y brancher (H6) ou s'en démarquer ?
5. ~~Clé API : `.env` ou Trousseau ?~~ → `.env` en H1, Trousseau reporté (H11).

## Journal

- **2026-10-11 — H0** : probe en lecture seule, Hermes passé en v0.21.6 (`main`), clé ajoutée à la main.
- **2026-10-11 — H1** : NotchNotch envoie la clé et la crée si absente ; NotchNotch n'écrit plus le plist du gateway. Testé : création de la clé au boot, 401 → réparation sans rotation, `.env` en 0600, plist intact, clé absente des logs. Ajouté au passage : toasts actionnables 8 s au lieu de 3 s. Non testé : onboarding sur une install neuve, génération du titre.
