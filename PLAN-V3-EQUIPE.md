# NotchNotch v3 : une équipe d'agents

Suivi de la v3 : des agents persistants (Léa, Max, Inès…) qui travaillent ensemble, orchestrés par Sam, et qui demandent au patron avant d'agir. Sources produit : le doc [NotchNotch - Plan de l'équipe d'agents](https://claude.ai/artifact/XgoUkR2CoUqYoxidzSg78x) et le canvas [NotchNotch - Équipe](https://claude.ai/artifact/X79UFvVcCYky4DhXWzX2ke). Ce fichier dit ce qui est vérifié, ce qui manque, ce qu'il reste à décider et dans quel ordre on le fait.

**Règle de travail** : lire ce fichier avant une session E ou P. À la fin, mettre à jour le tableau des sessions et le journal dans le même commit. Les faits Hermes ci-dessous viennent du code et des probes du 2026-10-23 (rapports : `~/Documents/notchnotch-probes/2026-10-23/`). Hermes est installé en v0.22.5 depuis E0a ; les lignes dont la source cite « E0a » y ont été revérifiées (`e0a-RAPPORT.md`).

## Verdict

Le plan est pertinent. Hermes v0.22 fournit déjà le moteur : profils isolés, tableau Kanban, répartiteur, découpe des demandes, questions bloquantes, notifications. Le probe Kanban du 23/10 a fait tourner la boucle complète : carte créée depuis le chat, prise seule par le bon profil, bloquée sur une question, débloquée depuis la conversation, terminée. NotchNotch n'a pas à écrire un orchestrateur : il doit installer l'équipe, la montrer et faire remonter les décisions.

Il manque au plan cinq choses pour marcher vraiment :

1. **Un vrai verrou sur « l'équipe prépare, le patron décide »**. Les approbations d'Hermes ne couvrent que les commandes dangereuses, et un agent du tableau tourne sans personne pour répondre. Le verrou doit être dans la structure (les agents n'ont aucun outil d'envoi), pas dans la consigne.
2. **Le passage des maquettes à Hermes** : où vit une fiche de poste, comment NotchNotch lit le tableau (aucune API REST), comment une réponse revient à l'agent sans un tour payant de Sam.
3. **Le coût** : Hermes n'a aucun budget par agent, et par défaut chaque carte terminée réveille Sam (un tour payant).
4. **La v2 existante** : le profil default porte la mémoire, Telegram, les missions et le cerveau. Le plan ne dit pas ce qu'ils deviennent quand Sam arrive.
5. **La confidentialité est un chantier à part entière**. Le filtre par substitution marche (0 fuite sur 75 valeurs), mais seulement si Hermes n'a plus aucune clé de fournisseur. Pour tous les utilisateurs, ça veut dire : NotchNotch fermé, plus aucun modèle ne répond. Ce n'est pas un « en parallèle » discret de la première version.

## Principe : natif d'abord

Décidé le 2026-10-23. NotchNotch s'appuie sur le cœur d'Hermes et rien d'autre : profils, tableau Kanban, répartiteur, missions par profil, routes `/p/<profil>/`. La délégation vers un profil n'en fait pas partie : le cœur v0.22.5 n'a que le point d'extension, le routage par profil est le plugin officiel `advanced-delegation` du catalogue (E0a). Il les installe, les montre et fait remonter les décisions. Il ne reconstruit pas ce qu'Hermes n'a pas.

- **Ce que le cœur ne fait pas, la v3.0 ne le fait pas** : pas de budget avec pause automatique, pas de filtre de confidentialité, pas d'envoi par NotchNotch. On affiche ce qu'Hermes sait (coûts, événements). Le reste attend un besoin prouvé ou une fonction d'Hermes.
- **Aucun plugin communautaire comme dépendance.** Le catalogue, installable en un clic depuis Desktop, contient des plugins proches de la v3. Ce ne sont pas des fonctions d'Hermes :

| Plugin (catalogue v0.22.5) | Qui | Ce qu'il fait | Pour NotchNotch |
|---|---|---|---|
| `bot-forge` | communauté (BkashJEE) | « make me a <role> » crée un agent complet (SOUL.md, mémoire, outils, routines), embauche une équipe, dit ce qui attend le patron | Valide l'idée. Inspiration pour le catalogue et l'onboarding, pas une dépendance : il écrit dans les profils, y installe ses propres hooks et envoie des emails par SMTP. |
| `hermes-teammates` | communauté | Sous-agents nommés avec leur modèle et leurs outils, voie Kanban avec remise en revue | Même idée, par des sous-agents en mémoire. Les profils natifs suffisent. |
| `inbox` | Hermes Labs (Nous), non supporté | Vue en lecture seule de tout ce qui est en cours (cartes bloquées, missions en échec, délégations perdues), avec `--json` | Proche de « Besoin de toi ». S'il entre dans le cœur, `KanbanStore` peut s'appuyer dessus. |
| `kanban-stream` | communauté | Suivi des cartes en direct sur Telegram, consignes par commentaire | Idée pour E15. Hermes sait déjà abonner Telegram à une carte. |
| `hermes-workflows` | communauté | Graphes d'agents avec portes humaines | Hors sujet pour la v3.0. |
| `advanced-delegation` | officiel (Nous), hors cœur | Modes de délégation `model_map` et `profile_routes` : un sous-agent tourne comme un de tes profils (`/delegation`, `hermes delegation config`) | C'est la « délégation par profil » des notes v0.22.5. Hors v3.0 (natif d'abord). |

- **Sans bordel** : chaque session touche le moins possible de fichiers d'Hermes, toujours par sa CLI (jamais en écrivant ses bases), et liste ses écritures dans CLAUDE.md.

## Ce qu'Hermes fait déjà

| Besoin du plan | Ce qu'Hermes offre (v0.22.5) | Source | Conséquence pour NotchNotch |
|---|---|---|---|
| Agents propres, avec leur mémoire et leur modèle | `hermes profile create <nom>` sans `--clone` : un dossier à part (mémoire, skills, cron, `state.db`, `SOUL.md`). Seul le bloc modèle du profil actif est recopié. `--clone` copie `MEMORY.md`, `USER.md`, le `.env` et la banque Hindsight cloud. Profil vierge : `.env` vide, **aucune clé de fournisseur héritée** du default (ni par `/p/`, ni dans le tableau), mémoire vide, pas de Hindsight, `approvals.mode: smart`, 58 skills. | code `hermes_cli/profiles.py`, `agent/secret_scope.py`, probe Kanban, E0a Q1 | Jamais `--clone`. Chaque agent a besoin de sa clé de fournisseur (nouvelle exception) et de `approvals.mode: manual`. Sans clé, la carte finit `blocked` avec une erreur opaque (« Kanban execution unknown ») : vérifier la clé avant d'assigner. Le 2ᵉ profil fait écrire `gateway.multiplex_profiles: true` au default (par Hermes). |
| Sam qui répartit | `kanban.orchestrator_profile`, `kanban.default_assignee`, découpe automatique des cartes « triage » par un LLM auxiliaire qui route d'après `hermes profile describe` | code `kanban_decompose.py`, probe T2 | Un objectif mixte reste une seule carte. Sam doit découper lui-même (une `kanban_create` par rôle), comme le dit le plan. |
| Bureau commun, relais tracés | Dépendances (`--parent`), commentaires, pièces jointes, événements, un run par passage, skills et modèle par carte | code `kanban_parser.py`, probe | Le journal d'activité existe déjà (`task_events`, `task_runs`). |
| Réveil sans consommer | Le répartiteur du gateway regarde le tableau toutes les 60 s, sans LLM, et lance un worker seulement s'il y a une carte prête. En v0.22.5 le worker fait jouer la carte par le gateway (RPC `kanban.run`, événement `owner_admitted`) dans le `state.db` du profil. | code `config_defaults.py`, `kanban_worker_client.py`, probe T1, E0a Q3 | Le « rythme de réveil à la Paperclip » est gratuit et déjà là. Seul le travail proactif (lire la boîte mail chaque matin) demande une mission récurrente. |
| « Besoin de toi » | `kanban_block(kind=needs_input, reason=<question>)` → événement `blocked` | probe T4, E0a Q3 | La question est dans l'événement. Le patron répond par `hermes kanban comment` + `unblock` (0,8 s chacun), sans LLM ; l'agent reprend au tick suivant (≤ 60 s) avec la réponse. |
| Relire le travail d'un autre | `kanban_request_review(reviewer=<profil>)` | code `kanban_tools_schemas.py`, E0a Q4 | `kanban.review_dispatch: true` (défaut) : un agent avec `sdlc-review` relit au tick suivant (un tour LLM) et peut approuver seul. Validation humaine = `review_dispatch: false` : la carte attend en `review` ; `complete` pour valider, `reopen-review --reason` pour renvoyer (`request-changes` est refusé hors d'une revue d'agent). |
| Retour dans la conversation | Une carte créée depuis le chat abonne la conversation. À la fin, le gateway joue un tour de Sam (`[kanban] Task … completed`) écrit dans `state.db`, rôle `user`. Rien n'est poussé au client. | probe T6, E0a Q5 | Un tour par carte (2 appels, ≈ 0,0013 $ en Haiku). `auto_subscribe_on_create: false` : 0 tour, la carte se termine pareil. `kanban_create` écrit sur le tableau courant (pas de paramètre de tableau). |
| Lire le tableau | Aucune route Kanban sur :8642. `hermes kanban … --json` répond en ≈ 0,7 s. SQLite en lecture seule échoue (code 14). PR amont NousResearch/hermes-agent#68200 « revision-aware Kanban API » toujours ouverte, sans revue, inchangée depuis le 2026-07-30. | probe T5, E0a Q9 | `KanbanStore` interroge la CLI. Déclencheur : date de `kanban.db` + taille de `kanban.db-wal` (102 événements sur 102 vus, 5 faux réveils sur 74) ; ignorer `-shm` et le dossier, qui bougent toutes les 5 s. |
| Parler à un agent | Le gateway sert tous les profils sur le même port (`gateway.multiplex_profiles`, toujours actif) : `/p/<profil>/v1/chat/completions`, avec la clé `API_SERVER_KEY` du `.env` du profil (la clé du default y est refusée, 401). Continuité par `X-Hermes-Session-Id`, `approval.request` dans le flux, coût dans le `state.db` du profil. | code `gateway/platforms/api_server.py`, E0a Q2 | Possible sans passer par Sam. Une clé par profil (nouvelle exception), prise en compte sans redémarrage. En v0.22.5, `session_key` et la réponse d'approbation changent (voir Nettoyage et dettes). |
| Tâches récurrentes par agent | Chaque profil a son `cron/jobs.json` ; le gateway unique les déclenche tous | code `gateway/run.py` (`_cron_profile_gate`), E0a Q6 | `CronStore` ne regarde que `~/.hermes/cron/` : à étendre. |
| Mettre en pause | `gateway.parked` (`hermes -p X gateway stop`) : `/p/X/` répond 404 et les missions s'arrêtent, mais le répartiteur prend encore les cartes de X, qui finissent `blocked` après ≈ 8 min (2 × attente de 180 s). `kanban.dispatch_profiles` : les cartes de X restent `ready`, missions et `/p/X/` continuent ; liste fermée (y mettre `default` et tous les autres agents). | code `kanban_db_dispatch.py`, `kanban_worker_client.py`, E0a Q6 | Pause = retirer X de `dispatch_profiles`, plus `gateway stop` si ses missions doivent s'arrêter (combinaison non testée). Chaque nouvel agent doit être ajouté à la liste. |
| Budget par agent | **Rien**. Seulement une alerte au choix d'un modèle très cher. Le coût est écrit dans le `state.db` de chaque profil, runs du tableau compris (`source=kanban`). | code `model_cost_guard.py`, E0a Q2 | Hors v3.0 : afficher le coût du mois par agent (E12). |
| Accord avant d'envoyer | Les approbations visent les commandes dangereuses (terminal), plus une mise en attente des écritures de mémoire et de skills (`write_approval`). Un agent du tableau tourne en `-q` : `approvals.single_query_mode: deny` par défaut, sans question. Un profil neuf est en `smart` : `rm -rf` auto-approuvé sans demander. | code `tools/approval_context.py`, `tools/write_approval.py`, E0a Q2 | Aucune garantie « rien ne part sans ton accord » côté Hermes. Voir A. |
| Sous-agents vers un profil | Cœur v0.22.5 : point d'extension (route `profile`) et backend `default` seulement. Le routage par profil est le plugin officiel `advanced-delegation` (catalogue). Une délégation ordinaire part en arrière-plan ; son résultat est écrit dans la conversation sans tour de réveil sur l'API. | code `agent/delegation_provider.py`, `plugin-catalog/advanced-delegation.yaml`, E0a Q8 | Hors v3.0 (natif d'abord). Dans le flux de NotchNotch, seulement `delegate_task` en cours puis terminé ; le résultat n'apparaît qu'au message suivant du patron. |
| Équipe dans Hermes Desktop | Bot Mode : les agents s'écrivent (`message_agent`), un « Bot Chat » par profil, discussions de groupe | code `tools/bot_mode_dm.py`, notes v0.22.5 | Desktop fait déjà une partie de l'idée. Le regarder avant de dessiner, pour se démarquer (E0b). |

## Ce qui manque au plan

### A. Le verrou sur ce qui sort
1. Les agents n'ont **aucun outil d'envoi** : pas de `send_message`, pas de Gmail en écriture, pas de navigateur pour publier. Ils écrivent des brouillons (pièce jointe de la carte, ou brouillon Gmail).
2. **Qui envoie ?** Pas l'agent : il faudrait lui donner l'outil. Natif d'abord : le patron lui-même. Le bouton ouvre le brouillon (Gmail, fichier) ou le copie. Un envoi par NotchNotch serait du code et une exception de plus : plus tard, si le besoin est prouvé. Décision D3.
3. En plus, une liste `approvals.deny` par profil pour les commandes d'envoi connues.
4. La fiche de poste dit ce qui demande un accord. NotchNotch ne le présente comme une garantie qu'une fois le point 1 en place.

### B. Brancher les maquettes sur Hermes
5. **Où vit une fiche de poste** : `profile.yaml` (description, sert au routage), `SOUL.md` (rôle, ton, règles), les skills du profil (procédures), ses réglages (modèle, outils, approbations). NotchNotch garde la version structurée (un fichier par rôle) et écrit ces fichiers à la validation. « Modifier en parlant » : Sam propose, NotchNotch montre la différence, le patron valide, NotchNotch écrit.
6. **Le contexte d'entreprise par rôle** : la mémoire d'un profil appartient à Hermes (règle actuelle). Proposition : un fichier de contexte par profil, écrit par NotchNotch et cité dans `SOUL.md`. Et le **cerveau** de la v2 (wiki, Clipper), que le plan ignore : dire qui le lit (Sam seul, ou tous), pour ne pas avoir deux bases de connaissances.
7. **Lire le tableau** : dédoublonner les événements (`show --json` ne donne pas leur id), lire le dernier `blocked` (`list --json` n'a pas `block_kind`), cacher l'onglet Équipe sous la version minimum.
8. **Répondre sans passer par Sam** : le bouton fait `hermes kanban comment` + `unblock`. Gratuit, immédiat, sans erreur d'aiguillage.
9. **Les tours `[kanban]`** dans la conversation de Sam : les afficher en ligne d'activité, pas en bulle du patron. Ou couper `kanban.auto_subscribe_on_create` et laisser NotchNotch annoncer la fin depuis le tableau. Décision D5.
10. **Activer le Kanban sur l'API** : `hermes tools enable kanban --platform api_server` fige la liste d'outils d'`api_server` et supprime `display.platforms` (inchangé en v0.22.5, E0a). Les futurs outils par défaut n'arrivent plus, sauf ceux qu'Hermes rallume pendant la version qui les livre (`_RECENTLY_SHIPPED_TOOLSETS`). `disable` ne retire que `kanban` : la liste figée reste. Aucun redémarrage.
11. **Limiter le travail en parallèle** : `kanban.max_in_progress` n'a aucun plafond sur macOS. Chaque agent est un process Python et des appels payants. Fixer 2 ou 3.
12. **Noms** : l'id du profil est en minuscules (`lea`), le nom affiché « Léa » (`hermes profile rename`). Couleur et avatar sont des métadonnées NotchNotch (clé UserDefaults à documenter).

### C. Le coût
13. **Budget par agent** : rien de natif, donc hors v3.0. On affiche le coût du mois par agent, lu dans chaque `~/.hermes/profiles/<p>/state.db`. Un coût inconnu n'est pas 0 (leçon de H8). Pas de plafond ni de pause automatique.
14. **Coût caché de Sam** : découpe automatique (LLM auxiliaire), tours `[kanban]`, synthèse des cartes racines. À mesurer (E3).
15. **Modèle par agent** : un modèle gratuit respecte-t-il le protocole du tableau (finir par `kanban_complete` ou `kanban_block`) ? Sinon : échec, deux essais (`kanban.failure_limit`), carte bloquée. À mesurer par rôle et par gamme de modèle (E3).

### D. La v2 existante
16. **Sam = le profil default** (décidé, D1) : il connaît déjà le patron, garde Telegram, les missions et le cerveau, et fait lui-même les petites choses. Le plan dit « il ne fait pas le travail des autres » : à nuancer, sinon un solo sans équipe n'a plus d'assistant.
17. **L'équipe est optionnelle** : l'onglet Équipe apparaît quand elle existe. Un utilisateur v2 qui n'en veut pas ne voit rien changer.
18. **Onboarding** : l'onboarding allégé (H14, en attente) et celui de l'équipe se pensent ensemble. L'équipe se propose après la première connexion, pas pendant.
19. **Mac en veille, app fermée** : le tableau et les missions tournent dans le gateway (launchd), pas dans l'app. Avec le filtre de confidentialité dans l'app, en revanche, app fermée = plus rien. À dire au patron.

### E. Interface
20. **Taille** : le Kanban des maquettes tient dans le panneau Large (860 × 560). Le Standard fait 640 × 340 : il faut une vue compacte (« Besoin de toi » et qui travaille), pas un panneau qui grandit tout seul (règle du projet). Décision D6.
21. **Design system** : les maquettes ne suivent pas `DesignSystem.swift` (accent ambre au lieu du bleu clair, boutons en pilule réservés aux puces d'état, cartes pleines au repos, police Inter). À traduire en `DS.*` avant de coder (E1).
22. **Notch fermé avec avatars** : la place réelle à côté de l'encoche est à vérifier sur un vrai Mac.
23. **Toasts** : un `ToastKind` pour l'équipe (ou réutiliser `chat` / `cron`), et la tape qui ouvre la bonne carte.
24. **Le téléphone** : le patron n'est pas toujours devant son Mac. Hermes sait abonner Telegram à une carte : « Léa a besoin de toi » sur le téléphone (E15).

### F. Qualité
25. **Un banc d'essai avant l'interface** (E3) : 30 demandes types, l'agent attendu, le coût, des cartes bien terminées, par gamme de modèle. Il dit si la promesse tient avec des modèles bon marché.
26. **Le catalogue de rôles est du contenu à écrire et tester** (E2) : fiche lisible, description de routage, `SOUL.md`, skills, outils permis et interdits, ce qui demande un accord, missions par défaut, questions d'onboarding, demandes de test.
27. **Probes sur le vrai Hermes** : jamais « retiens » (pollution de la mémoire), profils de test préfixés et supprimés à la fin.

### G. Règles du projet
28. La v3 change la nature de NotchNotch : il ne fait plus que parler à Hermes, il **administre** des profils. Chaque nouvelle écriture entre dans les exceptions de CLAUDE.md, dans le diff de la session qui l'ajoute (liste plus bas).

## Décisions

D1 à D6 validées par Jérémie le 2026-10-23. D7 reste ouverte : elle ne bloque qu'E11.

| # | Question | Décision | Statut | Ce que ça change pour le patron |
|---|---|---|---|---|
| D1 | Sam est-il le profil default, ou un nouveau profil ? | Default (Desktop fait de même, E0b) | ✅ décidé | Sam connaît déjà tout (mémoire, Telegram, missions). Avec un nouveau profil, il repartirait de zéro et le patron aurait deux assistants. |
| D2 | Confidentialité dans la v3.0 ou après ? | Après (rien de natif), en piste à part (P1 à P4). Dans la v3.0 : fiches de contexte par rôle (chaque agent ne sait que ce qu'il lui faut). | ✅ décidé | Avec le filtre : rien ne marche app fermée, et il faut retirer toutes les clés d'Hermes. Sans : les vrais noms partent au fournisseur, comme aujourd'hui. |
| D3 | Qui envoie ? | Le patron : le bouton ouvre ou copie le brouillon (natif d'abord, aucune exception) | ✅ décidé | Un agent ne peut rien envoyer seul, même s'il se trompe. Un clic de plus pour le patron. |
| D4 | Répondre à « Besoin de toi » : sur la carte ou via Sam ? | Sur la carte : `hermes kanban comment` + `unblock`, sans LLM (vérifié en E0a) | ✅ décidé | La réponse part tout de suite, sans coût ni mauvais aiguillage ; l'agent reprend dans la minute. |
| D5 | Carte terminée : NotchNotch l'annonce, ou Sam est réveillé ? | NotchNotch, depuis le tableau, avec `kanban.auto_subscribe_on_create: false` (0 tour, vérifié en E0a). Sam fait le point quand on le lui demande. | ✅ décidé | 0 tour payant par carte. En contrepartie, Sam n'apprend pas tout seul qu'une carte est finie. |
| D6 | Que montre le panneau Standard ? | Une vue compacte ; le Kanban complet en Large | ✅ décidé | Pas de panneau qui grandit tout seul. |
| D7 | Missions récurrentes : sur Sam ou sur chaque agent ? | Deux options. (a) Sam crée une carte pour l'agent à chaque échéance. (b) Routine dans le cron du profil de l'agent, sans carte, comme Desktop : plus natif (E0b). | ⏳ ouverte, à trancher avant E11 | (a) Tout passe par le tableau, un seul endroit à surveiller, mais l'agent ne « possède » pas sa mission. (b) L'agent a ses missions à lui, mais elles n'apparaissent pas sur le tableau. |

## Sessions

Statut : ⏳ à faire · 🟡 en cours · ✅ fait · ⏸ en attente.

| Session | Sujet | Dépend de | En parallèle avec | Statut | Commit |
|---|---|---|---|---|---|
| E0a | Probe v0.22.5 : profils vierges, `/p/<profil>/`, réponse sur la carte, revue humaine, coûts, pause, réglages Kanban | — | E0b, E1, E2 | ✅ | rapport `~/Documents/notchnotch-probes/2026-10-23/e0a-RAPPORT.md` (non commité) |
| E0b | Étude d'Hermes Desktop (Bot Mode, discussions de groupe, tableau) : quoi reprendre, où se démarquer | — | E0a, E1, E2 | ✅ | note `~/Documents/notchnotch-probes/2026-10-23/e0b-desktop.md` (non commité) |
| E1 | Maquettes v3 en `DS.*` : Standard compact, Large, notch fermé, carte « Besoin de toi », fiche de poste, onboarding, états vides et d'erreur | D1, D6 | E0a, E0b, E2 | 🟡 maquettes à valider | rangée V3 du canvas + note `~/Documents/notchnotch-probes/2026-10-23/e1-maquettes.md` (non commité) |
| E2 | Catalogue de rôles v1 (4 rôles) et leurs demandes de test | D1, D3 | E0a, E0b, E1 | ✅ | `bc81237` : `BoaNotch/Resources/Roles/` + `scripts/check-roles.py` (branche `claude/festive-swanson-61849d`) |
| E3 | Banc d'essai de l'équipe : routage, protocole, coût, par gamme de modèle | E0a, E2 | E4, E5 | ⏳ | |
| E4 | `TeamService` : créer, décrire, renommer, mettre en pause, supprimer un agent ; réglages `kanban.*` | E0a, E2 | E3, E5 | ⏳ | |
| E5 | `KanbanStore` : lire le tableau, répondre sur la carte, tours `[kanban]` | E0a | E3, E4 | ⏳ | |
| E6 | Onboarding de l'équipe : questionnaire de Sam, proposition structurée, création, documents | E1, E2, E4 | E7 | ⏳ | |
| E7 | Onglet Équipe : Kanban Large, vue compacte, notch fermé, toasts | E1, E5 | E6 | ⏳ | |
| E8 | Validations de ce qui sort : agents sans outil d'envoi, brouillons, bouton qui ouvre ou copie le brouillon | E0a, E4, E7 | E9, E11 | ⏳ | |
| E9 | Fiches de poste : écran Équipe, modifier en parlant, pause, départ (avec export) | E4, E6 | E8, E11 | ⏳ | |
| E11 | Missions récurrentes par agent (`CronStore` multi-profils, Missions par agent) | D7, E4, E5 | E8, E9 | ⏳ | |
| R | Sortie v3.0 : version, notes de version, garde de compatibilité | E0a à E9, E11 | — | ⏳ | |
| E10 | Parler à un agent depuis sa colonne | E5, E7 | E12 à E15 | ⏳ | |
| E12 | Coût du mois par agent (lecture seule). Budget, alerte et pause automatique hors v3 (rien de natif) | E4, E11 | E10, E13 | ⏳ | |
| E13 | Journal d'activité et « Sam fait le point » | E5 | E12 | ⏳ | |
| E14 | Les corrections du patron améliorent les fiches | E3, E9 | E15 | ⏳ | |
| E15 | « Besoin de toi » sur le téléphone (Telegram) | E5 | E14 | ⏳ | |
| P1 | Relais de substitution dans l'app (Swift, clés dans le Trousseau), correctifs initiale et casse | D2 | piste équipe | ⏳ | |
| P2 | Zéro clé hors relais : `.env`, `auth.json`, environnement du gateway, menu des modèles, `--provider` des cartes, Hindsight | P1 | piste équipe | ⏳ | |
| P3 | Le coffre : clients et contacts, règles de format, suggestions pour les noms inconnus | P1 | P2 | ⏳ | |
| P4 | Mode confidentiel et preuve visible (« ce qui a quitté ton Mac aujourd'hui ») | P2, P3 | — | ⏳ | |

### Ordre

1. **Vague 1, sans code dans l'app** : E0a et E0b faites ; E1 et E2 peuvent démarrer en parallèle (D1 à D6 tranchées le 2026-10-23).
2. **Vague 2** : E3, E4, E5. E4 et E5 créent surtout des fichiers neufs, mais touchent tous deux `AppDelegate` et CLAUDE.md : un worktree chacun, fusion l'une après l'autre.
3. **Vague 3** : E6 et E7.
4. **Vague 4** : E8, E9, E11, puis R (v3.0).
5. **Ensuite** : E10, E12 à E15. La piste P (hors v3, rien de natif, D2) ne démarre qu'après la v3.0, indépendamment de la piste équipe (E4 doit seulement permettre un `model.base_url` par profil).

### Détail

**E0a · Probe v0.22.5** (aucun fichier de code modifié ; seul ce plan est mis à jour)
- Demander avant de mettre Hermes à jour en v0.22.5. Supprimer les profils de test restants (`hermes profile delete nn-subst -y`, `hermes profile delete nn-direct -y`).
- Profil vierge `nn-e0-…` : quelle clé et quel modèle il utilise, mémoire vide, Hindsight absent, outils par défaut.
- `/p/<profil>/v1/chat/completions` : clé du profil, continuité de session, `approval.request`, coût écrit dans le `state.db` du profil.
- Carte bloquée, puis `hermes kanban comment` + `unblock` en CLI : l'agent reprend-il avec la réponse ?
- Revue humaine : `kanban_request_review` sans relecteur, `review_dispatch` vrai puis faux ; `complete` et `request-changes` en CLI.
- `auto_subscribe_on_create` vrai puis faux : nombre et coût des tours `[kanban]`.
- Pause : `gateway.parked` contre `kanban.dispatch_profiles`, effet sur les missions du profil.
- `hermes tools enable kanban --platform api_server` sur v0.22.5 : ce qu'il réécrit encore.
- Délégation vers un profil (v0.22.5) : visible dans le flux de NotchNotch ?
- Lecture : temps de `kanban list` et `show --json`, date de modification de `kanban.db` comme déclencheur, état de la PR #68200.
- Fini quand : rapport dans `~/Documents/notchnotch-probes/<date>/`, mémoire projet à jour, colonne « Source » du tableau « Ce qu'Hermes fait déjà » corrigée.

**E0b · Hermes Desktop**
- Lire `apps/` du dépôt Hermes (et l'app si elle est installée) : Bot Mode, « Bot Chat », discussions de groupe, tableau du dashboard.
- Fini quand : une page « ce que Desktop fait / ce que NotchNotch fait autrement », avec captures si possible.

**E1 · Maquettes**
- Reprendre le canvas « NotchNotch - Équipe » : `AppColors.accent`, boutons `DS.Radius.button`, listes à filets, pas de carte pleine au repos.
- Écrans : notch fermé (avatars + pastille), Standard compact, Large (vue d'ensemble, agent agrandi), carte « Besoin de toi » avec son brouillon, fiche de poste, onboarding de l'équipe, états vides et d'erreur (gateway arrêté, agent en pause, budget atteint).
- Fini quand : maquettes validées par Jérémie ; tokens manquants listés pour `DesignSystem.swift`.

**E2 · Catalogue de rôles**
- 4 rôles (commercial, compta, communication, admin). Pour chacun : fiche en français, description de routage (1 à 2 phrases), `SOUL.md`, skills, outils permis et interdits, ce qui demande un accord, missions par défaut, questions d'onboarding, 10 demandes de test avec l'agent attendu.
- Un fichier par rôle dans `BoaNotch/Resources/Roles/`, lu via `Bundle.main.resourceURL` (jamais `Bundle.module`).
- Fini quand : relu par Jérémie, utilisable par E3 et E4.

**E3 · Banc d'essai**
- Un script dans `scripts/` : crée les profils du catalogue (préfixe `nn-eval-`) et un tableau de test, envoie les demandes à Sam, attend les cartes, note l'aiguillage, la fin correcte, le coût et la durée. Supprime tout à la fin.
- Au moins deux gammes de modèles (bon marché, gratuit).
- Fini quand : tableau de résultats, seuil d'acceptation décidé (par exemple 90 % de bon aiguillage), banc relançable après chaque changement de fiche.

**E4 · TeamService**
- Service `@MainActor` : `hermes profile create/describe/rename/delete/export` ; écriture de `SOUL.md`, des outils, des approbations et de la clé API du profil ; réglages `kanban.*` (`orchestrator_profile`, `max_in_progress`, `auto_decompose`, `review_dispatch`, `auto_subscribe_on_create`, `dispatch_profiles` pour la pause) ; activation du Kanban sur `api_server`. Une clé de fournisseur et `approvals.mode: manual` par profil (E0a).
- Métadonnées NotchNotch (couleur, rôle du catalogue) ; clé UserDefaults documentée dans CLAUDE.md.
- Exceptions CLAUDE.md ajoutées dans le même diff.
- Fini quand : créer, modifier, mettre en pause et supprimer un agent depuis l'app, vérifié par `hermes profile list` et une carte qui tourne.

**E5 · KanbanStore**
- Interroge `hermes kanban --json` quand le tableau change et à l'ouverture du notch. Modèles des cartes et événements ; états « besoin de toi », « en cours », « à faire », « terminé ».
- Actions : répondre (commentaire + reprise), valider ou renvoyer une revue, archiver.
- Tours `[kanban]` dans la conversation de Sam : une ligne d'activité, pas une bulle du patron.
- Garde de version : onglet caché si Hermes est trop ancien.
- Fini quand : les scénarios T3 et T4 du probe Kanban rejoués depuis l'app.

**E6 · Onboarding de l'équipe**
- Sam pose les questions en conversation. La proposition d'équipe sort en JSON (`sendCompletion`, format strict, validation, une relance) à partir du catalogue. NotchNotch l'affiche avec Valider, Retirer, Ajouter.
- Les profils sont créés par `TeamService`, pas par Sam : nom, couleur, fiche.
- Documents d'entreprise : Sam propose le contexte de chaque rôle, le patron valide, NotchNotch écrit.
- S'accorder avec H14 : l'équipe se propose après la première connexion.
- Fini quand : un compte neuf passe de zéro à une équipe de 3 qui traite une première demande.

**E7 · Onglet Équipe**
- Large : une colonne par agent ; un agent agrandi, les autres en bandes. Standard : vue compacte.
- Notch fermé : avatars de ceux qui travaillent, pastille « besoin de toi ». Toasts « Léa a besoin de toi », « Max a terminé le bilan ».
- `scripts/lint-design.sh`, `FadingScrollView`, `notchPanelInsets`.
- Fini quand : testé sur un vrai tableau, aux deux tailles.

**E8 · Validations de ce qui sort**
- Outils de chaque agent limités par son rôle (aucun envoi) ; `approvals.deny` pour les commandes d'envoi connues.
- Brouillons : pièce jointe de la carte ou brouillon Gmail. Le bouton ouvre le brouillon (Gmail, Aperçu) ou le copie ; le patron envoie lui-même. NotchNotch n'envoie rien.
- Fini quand : un agent à qui on dit « envoie-le directement » ne peut pas, et le bouton ouvre le bon brouillon.

**E9 · Fiches de poste**
- Écran Équipe : fiche lisible ; modifier en parlant (Sam propose, différence affichée, NotchNotch écrit) ; pause et reprise ; départ avec export (`hermes profile export`) et confirmation.
- Fini quand : modifier une fiche change l'aiguillage au banc d'essai.

**E11 · Missions par agent**
- Trancher D7 d'abord. Puis : `CronStore` lit le `cron/jobs.json` de chaque profil ; Missions groupées par agent ; création et suppression toujours par le chat ; toast d'échec au nom de l'agent.
- Fini quand : « Léa relance les devis le lundi » crée la mission, puis une carte pour Léa le lundi.

**E10 · Parler à un agent**
- Piste la plus native (E0b, à confirmer en direct) : un commentaire sur une carte **en cours** est injecté dans le tour du worker en quelques secondes (`tools/kanban_tools.py:609-656`), sans bloquer ni débloquer. E10 se réduirait à un champ de commentaire dans la colonne. Sinon : conversation directe sur `/p/<profil>/`. Décider comment Sam en est informé.
- Fini quand : une consigne à Léa change sa carte en cours.

**E12 · Coût par agent**
- Coût par profil depuis chaque `state.db` (logique de H8), mois en cours, « inconnu » affiché comme tel. Pas de budget ni de pause automatique tant qu'Hermes n'en a pas.
- Fini quand : simulé sur une copie des bases.

**E13 · Journal et point** : journal depuis `task_events` et `task_runs` (qui, quand, depuis quelle demande via `tasks.session_id`). « Sam fait le point » = une demande à Sam, qui lit le tableau.

**E14 · Corrections** : « ça aurait dû aller à Max » réassigne la carte, propose une nouvelle description, relance le banc.

**E15 · Téléphone** : abonner Telegram aux cartes bloquées (`hermes kanban notify-subscribe`), répondre depuis le téléphone.

**P1 à P4 · Confidentialité** : partir de la section 8 de `substitution-RAPPORT.md`. Les points durs : Hermes ne doit voir **aucune** clé hors du relais (le menu des modèles du notch et le `--provider` d'une carte passaient à côté, S9a) ; vérifier si le gateway launchd hérite des variables de `~/.zshrc` ; substituts qui gardent l'initiale et la casse ; raisonnement affiché avec les noms fictifs, à restaurer pour l'affichage seulement ; messages en français pour un envoi bloqué et pour le 401 ; politique pour Hindsight et les outils réseau ; ce que voit un utilisateur existant à la migration.

## Première version (v3.0)

- **Dedans** : Sam (profil default) et 3 rôles du catalogue, l'onboarding de l'équipe, « Besoin de toi » avec réponse sur la carte, l'onglet Équipe (Large et compact), les validations structurelles (E8), les fiches de poste, les missions récurrentes par agent, le banc d'essai.
- **Ensuite** : parler à un agent depuis sa colonne, le coût par agent, le journal détaillé, les corrections qui font évoluer les fiches, le téléphone.
- **Hors v3 (rien de natif)** : la confidentialité (P1 à P4), le budget avec pause automatique, l'envoi par NotchNotch.
- **Retirés** : l'organigramme (peu utile pour 3 ou 4 agents) et un « rythme de réveil » propre à NotchNotch (le répartiteur d'Hermes le fait déjà, gratuitement).

## Exceptions CLAUDE.md à ajouter (au fil des sessions)

| Écriture | Session |
|---|---|
| `hermes profile create/describe/rename/delete/export` | E4 |
| `SOUL.md`, outils, approbations et `model.*` d'un profil | E4, P2 |
| `API_SERVER_KEY` dans le `.env` de chaque profil | E4 |
| Clé de fournisseur de chaque profil (`.env` du profil ou `hermes -p X auth add`) | E4 |
| `kanban.*` dans `config.yaml` (dont `dispatch_profiles`) | E4 |
| `hermes -p X gateway stop/start` (pause des missions et de `/p/X/`) | E4 |
| `hermes tools enable kanban --platform api_server` | E4 |
| `skills.disabled`, `agent.disabled_toolsets`, `approvals.deny` d'un profil, et `hermes -p X skills install official/… --yes` (catalogue E2) | E4 |
| `hermes kanban comment/unblock/complete/reopen-review/archive` | E5 |
| Fichier de contexte d'entreprise par profil | E6 |
| Relais de substitution, clés dans le Trousseau, retrait des clés du `.env` et d'`auth.json` (hors v3) | P1, P2 |

## Nettoyage et dettes liées

- ✅ Profils de test `nn-subst` et `nn-direct` supprimés par E0a (2026-10-23).
- ✅ Hermes mis à jour en v0.22.5 par E0a (2026-10-23 ; instantané `~/.hermes/state-snapshots/20261023-143714-pre-update-e0a`). `/health` affiche encore `0.22.2` jusqu'au prochain `hermes gateway restart` : la version est mise en cache au démarrage, et le gateway a redémarré avant que la mise à jour écrive le tag.
- ✅ **Régression v2 (v0.22.5), corrigée par H16** (`d6745ec`, testé dans le notch) : `HermesClient.respondToApproval` renvoie `execution_generation` copié de l'événement `approval.request` (sans lui, 400 et tour bloqué).
- ✅ **Régression v2 (v0.22.5), corrigée par H16** : les nouvelles lignes de `state.db` ont `session_key` = `agent:main:api_server:dm:notchnotch-<uuid>`. `SessionStore.latestRowId` lit d'abord le registre `state_meta` `gateway.api.conversation.v1.<clé>`, puis `session_key` brut ou finissant par `:<clé>` ; l'historique extrait la clé des trois formes. H16 a aussi branché le Stop sur `POST /v1/runs/{id}/stop`.
- Conversations de test d'E0a dans `~/.hermes/state.db` (4 conversations et une session enfant, ids dans le rapport) : à supprimer au besoin avec `hermes sessions delete`.
- H14 (onboarding allégé) attend ses questions ouvertes 3, 6 et 7 : à trancher avant E6.
- Le gateway « canonical » est arrivé dès la v0.22.5 (H16 fait). Reste à revérifier en E5 : avec la nouvelle identité de session, le lien carte → conversation (`tasks.session_id`) et les tours `[kanban]`. Re-probe à la sortie de v0.23.0.
- Clipper : toujours en 401 (pas de `API_SERVER_KEY`).

## Journal

- **2026-10-23** : revue du plan produit et des maquettes, vérification dans le code d'Hermes v0.22.2 (profils, `/p/<profil>/`, approbations des agents du tableau, `review_dispatch`, budgets, missions par profil) et dans les trois probes du jour. Rapports copiés de `/tmp` vers `~/Documents/notchnotch-probes/2026-10-23/`. Découpage en sessions E0a à E15 et P1 à P4. Décisions D1 à D7 en attente.
- **2026-10-23 (E0b)** : étude d'Hermes Desktop faite dans le code v0.22.2 et les docs (app non installée : seul l'installeur `Hermes-Setup` est présent, donc aucune capture de l'app). Bot Mode = profils nommés, Bot Chat permanent, `message_agent`, salles de 2 à 6 agents, routines par agent ; Kanban = plugin séparé, éteint par défaut, sans lien avec les agents ; ni chef, ni budget par agent, ni verrou d'envoi, Bots et Kanban en anglais seulement. À reprendre : commentaire sur une carte en cours injecté dans le travail de l'agent (E10), annonces par flux d'événements à curseur (D5), signaux « qui travaille », raisons d'échec typées. Desktop est à l'opposé de D7 (routine sur l'agent) et clone la mémoire du patron par défaut. Détail : `~/Documents/notchnotch-probes/2026-10-23/e0b-desktop.md`.
- **2026-10-23** : principe « natif d'abord » retenu par Jérémie. Les plugins du catalogue v0.22.5 qui ressemblent à la v3 (`bot-forge`, `hermes-teammates`, `inbox`) sont communautaires ou non supportés, pas du cœur d'Hermes : inspiration seulement. Conséquences : NotchNotch n'envoie rien (D3), budget et confidentialité hors v3 (rien de natif). E0a arrêtée avant la mise à jour d'Hermes ; E0b étend son étude à ces plugins.
- **2026-10-23 (E0a)** : Hermes mis à jour en v0.22.5 (accord de Jérémie), probe des fonctions du cœur seulement. Profil vierge : aucune clé héritée, `approvals.mode: smart` (auto-approuve). `/p/<profil>/` : clé du profil obligatoire, continuité et coût OK. Réponse sur la carte (`comment` + `unblock`) : OK sans LLM. Revue humaine : `review_dispatch: false`, puis `complete` ou `reopen-review` (pas `request-changes`). `auto_subscribe_on_create: false` : 0 tour `[kanban]` (sinon ≈ 0,0013 $ par carte). Pause : `dispatch_profiles` gèle les cartes, `gateway.parked` les laisse prendre puis bloquer. `tools enable` inchangé. La délégation par profil est un plugin du catalogue, pas le cœur. Lecture : CLI en 0,7 s, déclencheur `kanban.db` + `-wal`. Deux régressions v2 trouvées (approbations en 400, `session_key`). Rapport : `~/Documents/notchnotch-probes/2026-10-23/e0a-RAPPORT.md`.
- **2026-10-23** : décisions D1 à D6 validées par Jérémie telles que recommandées (Sam = default ; confidentialité après la v3.0 ; le patron envoie lui-même ; réponse sur la carte ; fin de carte annoncée par NotchNotch avec `auto_subscribe_on_create: false` ; vue compacte en Standard). D7 reste ouverte (carte créée par Sam, ou routine dans le cron du profil comme Desktop) : à trancher avant E11. E1 et E2 peuvent démarrer.
- **2026-10-23 (E2)** : catalogue v1 écrit, à relire par Jérémie : Léa (commercial), Max (compta), Inès (communication), Hugo (admin), un YAML par rôle dans `BoaNotch/Resources/Roles/` avec son `README.md`, copiés dans `Contents/Resources/Roles/` par `run.sh` et `release.sh`. Chaque fiche : fiche lisible, description de routage, `SOUL.md`, skills livrés, toolsets interdits, `approvals.mode: manual` et 48 motifs `approvals.deny`, accords, missions (D7 ouverte), onboarding, contexte, 10 tests dont 3 ambigus. Domaines exclusifs (refus d'un rôle qui en recouvre un autre) et empreinte de la fiche (SHA-256 sur 12 caractères, recopiée dans `metadata.fiche` de chaque carte). `scripts/check-roles.py` vérifie les fiches contre l'Hermes local, en lecture seule. Constats : une carte tourne avec les outils de la plateforme `cli`, pas `api_server` ; `agent.disabled_toolsets` les retire partout ; `gmail.modify` permet d'envoyer et le skill `google-workspace` n'a pas de brouillon, d'où « aucun jeton Google chez les agents » ; un agent peut lancer `hermes tools enable` ou `hermes send` (motif `hermes*`) ; le `SOUL.md` d'un profil n'est pas protégé par `protected_instruction_files`, contrairement à la note 4 d'E0b (à confirmer en E3).
- **2026-10-23 (E2)** : catalogue v1 validé par Jérémie. Les questions ouvertes du README des rôles (fin de carte par `kanban_complete` ou par la revue humaine, `skills.write_approval`, cerveau réservé à Sam) restent à trancher en E4 et E8.
- **2026-10-23 (E1)** : maquettes v3 en `DS.*` publiées sur le canvas, rangée « V3 · design system » (14 plans) : notch fermé, toasts, Standard compact et ses états (rien à décider, sans clé, sans nouvelles, en pause, Hermes arrêté), quatre variantes de « Besoin de toi » (question avec brouillon, réglages, réessayer, même question deux fois), Large (vue d'ensemble, agent agrandi), fiche de poste, onboarding. Constat : `AppColors.accent` est blanc dans le code depuis le 12/10 (`109a37c`), CLAUDE.md dit encore bleu clair ; les maquettes suivent le code, le bleu est en option dans les Tweaks. Jérémie a tranché : accent blanc, CLAUDE.md corrigé. 16 tokens ou primitives manquants (couleurs et tailles d'avatar, `DS.Status.warning` et `problem`, `SecondaryButtonStyle`, `ToastKind.team`…). Pas d'état « budget atteint » (hors v3.0). À valider par Jérémie. Note : `~/Documents/notchnotch-probes/2026-10-23/e1-maquettes.md`.
- **2026-10-23** : `docs/plan-v3` fusionné dans master (`aec4f31`), sans conflit dans CLAUDE.md. Les deux régressions v0.22.5 de la v2 sont marquées corrigées par H16 (`d6745ec`).
