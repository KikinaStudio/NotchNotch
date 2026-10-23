# Catalogue de rôles (format 1)

Les rôles prêts à l'emploi de l'équipe v3 : un fichier par rôle. `TeamService` (E4) en fait des profils Hermes, l'onboarding (E6) y prend ses questions, le banc d'essai (E3) ses demandes de test, l'écran Équipe (E9) la fiche lisible. Principe : natif d'abord. Chaque champ correspond à un réglage ou à un fichier qu'Hermes connaît déjà (vérifié sur Hermes v0.22.5).

| Fichier | Rôle | Prénom par défaut | Profil proposé |
|---|---|---|---|
| `commercial.yaml` | Commercial | Léa | `lea` |
| `compta.yaml` | Compta | Max | `max` |
| `communication.yaml` | Communication | Inès | `ines` |
| `admin.yaml` | Admin | Hugo | `hugo` |

Les prénoms sont ceux du canvas « NotchNotch - Équipe ». Personnages fictifs.

**Pourquoi YAML** : NotchNotch lit déjà le YAML avec Yams (`HermesConfig`), le texte long de `SOUL.md` reste lisible en bloc `|`, et les commentaires guident la relecture ; le JSON n'a ni l'un ni l'autre. Les clés sont en anglais, avec les noms qu'utilise Hermes (`description`, `skills`, `toolsets`, `approvals`) ; les textes sont en français. Les 4 fichiers se décodent tels quels avec `YAMLDecoder` dans des structures `Decodable` dont les propriétés portent les noms des clés (essayé avec le Yams de `.build/checkouts`).

## Dans l'app

- Source : `BoaNotch/Resources/Roles/<id>.yaml`. `scripts/run.sh` et `scripts/release.sh` les copient dans `Contents/Resources/Roles/` (ce README n'est pas copié). Avant ce dossier, les scripts ne copiaient que des fichiers à plat par extension (`*.png`, `*.json`, `*.svg`…).
- Lecture (E4) : `Bundle.main.resourceURL?.appendingPathComponent("Roles")`, puis chaque `*.yaml`. Jamais `Bundle.module` (CLAUDE.md).
- `Package.swift` copie aussi `Resources/` dans le bundle SPM (`.copy("Resources")`), qui n'est pas utilisé.

## Les champs

| Clé | Type | Sert à | Dans Hermes (E4) |
|---|---|---|---|
| `format` | entier | version du format (1) | — |
| `id` | texte | identifiant du rôle dans le catalogue, = nom du fichier | métadonnée NotchNotch |
| `version` | entier | à incrémenter à la main à chaque changement de contenu | — |
| `default_name`, `pronoun` | texte | prénom et pronom par défaut (UI, onboarding) | `hermes profile rename` si le patron change le prénom (plan, point 12) |
| `default_profile` | texte | id du profil proposé (`[a-z0-9_-]`) | `hermes profile create <profil>` |
| `title` | texte | libellé court sous le prénom | — |
| `summary` | texte | fiche lisible, 2 ou 3 phrases, dite au patron | — |
| `description` | texte | description de routage, 1 ou 2 phrases | `profile.yaml` : `hermes profile create … --description` ou `hermes profile describe <p> --text` (`description_auto: false`). Le décomposeur la lit (`- <profil>: <description>`, `kanban_decompose.py`), Sam aussi. |
| `team_line` | texte | ce que fait ce rôle, en quelques mots | sert à construire `{{team}}` chez les autres |
| `domains` | liste | domaines exclusifs (voir « Pas de recouvrement ») | métadonnée NotchNotch |
| `not_mine` | liste `{topic, role}` | ce qui revient à un autre rôle | — (déjà dans `soul`) |
| `soul` | texte | modèle de `SOUL.md`, avec des marqueurs `{{…}}` | `~/.hermes/profiles/<p>/SOUL.md`, marqueurs remplacés |
| `skills.bundled` | liste | skills livrés (`skills/`), déjà présents dans tout profil neuf | liste blanche : `skills.disabled` = skills installés − cette liste − `optional` (`hermes-agent` ne peut pas être coupé) |
| `skills.optional` | liste `{name, install}` | skills officiels optionnels (`optional-skills/`) | `hermes -p <p> skills install <install> --yes` |
| `toolsets.denied` | liste | outils retirés | `agent.disabled_toolsets` (voir « Le verrou ») |
| `toolsets.allowed` | liste | outils qui doivent rester | rien à écrire : à vérifier avec `hermes -p <p> tools list --platform cli` |
| `approvals.mode` | texte | toujours `manual` | `approvals.mode` (un profil neuf est en `smart`, qui auto-approuve) |
| `approvals.deny` | liste | motifs des commandes d'envoi connues | `approvals.deny` |
| `needs_approval` | liste | ce qui demande l'accord du patron, dit au patron | — (déjà dans `soul`) |
| `missions` | liste | missions récurrentes proposées | voir « Missions » |
| `onboarding.questions` | liste | questions que Sam pose à la création du rôle (E6) | — |
| `context.needs` | liste `{id, label}` | ce que le fichier de contexte de l'agent doit contenir | fichier de contexte (E6) |
| `context.must_not_know` | liste `{label, why}` | ce qui n'y entre pas (D2) | — |
| `tests` | liste | 10 demandes de test pour E3 | — |

Une question d'onboarding a `id`, `question`, `why` (pourquoi on la pose), `feeds` (l'`id` de `context.needs` qu'elle remplit), `required` et parfois `default`. Un test a `request`, `expected` (un `id` de rôle, ou `sam` pour le profil default quand aucun rôle ne doit la prendre) et, s'il est ambigu, `ambiguous_with` et `why` ; `behavior` dit ce que l'agent doit faire ou ne pas faire (souvent : ne rien envoyer).

## Marqueurs de `soul`

| Marqueur | Remplacé par (E4) |
|---|---|
| `{{name}}` | le prénom de l'agent |
| `{{company}}` | le nom de l'entreprise |
| `{{owner}}` | le prénom du patron ; s'il est inconnu : « la personne qui dirige l'entreprise » |
| `{{context_file}}` | le chemin absolu du fichier de contexte de l'agent. Proposition : `~/.hermes/profiles/<p>/contexte-entreprise.md` (à trancher en E6) |
| `{{team}}` | une ligne par autre agent, `- <prénom> (<title>) : <team_line>`, puis `- Sam : le bras droit de <owner>, pour tout ce qui ne revient à personne d'autre.` |
| `{{fingerprint}}` | l'empreinte de la fiche |

Le `SOUL.md` est écrit au neutre (« tu t'occupes du commercial ») pour rester juste si le patron change le prénom.

## Empreinte

Empreinte = les 12 premiers caractères hexadécimaux du SHA-256 des octets du fichier :

```bash
shasum -a 256 BoaNotch/Resources/Roles/commercial.yaml | cut -c1-12
```

E4 la met dans `SOUL.md` (`{{fingerprint}}`) et la garde dans ses métadonnées. L'agent la recopie dans `metadata.fiche` de chaque `kanban_complete`, lisible dans `hermes kanban show --json` : on sait quelle version de la fiche a produit quelle carte (banc E3, corrections E14). Toute modification du fichier, commentaires compris, change l'empreinte. Une fiche modifiée par le patron (E9) prend l'empreinte du YAML modifié. Idée reprise de `hermes-teammates` (`role_hash`), sans le plugin.

## Pas de recouvrement entre rôles

Chaque rôle déclare ses `domains`. **Deux agents d'une même équipe ne partagent aucun domaine** : E4 et E6 refusent de créer un rôle qui en recouvre un autre, et proposent plutôt de modifier la fiche existante. Un rôle sur mesure (E6 « Ajouter », E9) choisit ses domaines dans ce vocabulaire, ou en ajoute un nouveau. Idée reprise de `bot-forge`, sans le plugin.

| Rôle | Domaines |
|---|---|
| commercial | `devis`, `relances_devis`, `prospects`, `suivi_clients`, `rendez_vous_clients`, `demandes_commerciales` |
| compta | `facturation`, `impayes`, `depenses`, `banque`, `tva`, `tresorerie`, `expert_comptable` |
| communication | `reseaux_sociaux`, `newsletter`, `site_web`, `avis_en_ligne`, `visuels`, `supports_presentation`, `veille_concurrents` |
| admin | `echeances`, `contrats`, `assurances`, `abonnements`, `courriers_administratifs`, `achats`, `deplacements`, `agenda`, `classement` |

Règles d'arbitrage, reprises dans les descriptions, les `SOUL.md` et les tests ambigus :

- Un devis pas encore signé est commercial ; signé, il devient une facture : compta. Relancer un devis : commercial ; relancer une facture impayée : compta.
- Préparer le contenu d'un rendez-vous client : commercial ; caler le créneau : admin.
- Un texte public (réseaux, site, newsletter, avis en ligne) est de la communication, même s'il parle d'une vente ; un message à un client précis est commercial.
- Un contrat, une assurance, un abonnement, une résiliation : admin ; le montant, la facture, le paiement : compta.
- Comparer et préparer un achat : admin ; payer : personne (le patron).
- Veille sur les concurrents : communication ; trouver des prospects : commercial.
- Une conversation avec le patron (« rappelle-moi ce qu'on s'est dit ») : Sam.

## Le verrou « rien ne sort »

Du plus solide au plus fragile :

1. **Aucun outil d'envoi.** Le cœur d'Hermes n'a pas d'outil d'envoi pour l'agent (« deliberately no agent-callable send_message tool », `toolsets.py`). `toolsets.denied` retire en plus `browser` (formulaires, publication), `connections` (brancher un compte ou un serveur MCP), `code_execution` (du Python hors du terminal, qui échappe aux motifs), `delegation` (sous-agents, +26 à 44 % de jetons d'après `hermes-teammates`), `cronjob` (`--deliver telegram`), `computer_use` et `clarify` (sans personne pour répondre sur une carte). `agent.disabled_toolsets` est retiré en dernier sur **toutes** les plateformes (`tools_config.py`). Ça compte : une carte du tableau tourne avec les outils de la plateforme `cli` plus `kanban` (`gateway/session_kanban.py`), et une conversation `/p/<profil>/` avec ceux d'`api_server`.
2. **Aucun identifiant d'envoi dans le profil.** Le `.env` d'un profil neuf est vide (E0a). **Constat** : le jeton Google de NotchNotch a le droit `gmail.modify`, qui permet d'envoyer, et aucun droit Gmail ne permet d'écrire un brouillon sans pouvoir envoyer. Le skill livré `google-workspace` n'a d'ailleurs pas de commande de brouillon (seulement `send` et `reply`). Proposition pour la v3.0 : aucun jeton Google dans les profils des agents (Gmail reste à Sam) ; un brouillon est un fichier joint à la carte (`artifacts` de `kanban_complete`). `google-workspace`, `himalaya`, `xurl` et `imessage` sont livrés dans tout profil neuf : ils sortent par `skills.disabled`.
3. **`approvals.deny`.** Globs `fnmatch`, insensibles à la casse, comparés à la commande entière et à chaque sous-commande ramenée au nom de son exécutable (`tools/approval_floors.py`, `tools/approval_detection.py`). Ils bloquent même en mode `off`. Ils couvrent l'e-mail, les messages, les réseaux sociaux, les partages, les paiements, et un verrou : `hermes*` (sinon un agent peut lancer `hermes tools enable browser`, qui le retire aussi d'`agent.disabled_toolsets`, ou `hermes -p default send`, qui part avec le Telegram du default), les `config.yaml` et `.env` d'Hermes, et `SOUL.md`. Limite : ils ne voient que le terminal. Un script écrit dans un fichier puis lancé leur échappe, et `write_file` aussi. Liste non exhaustive.
4. **`approvals.mode: manual`.** Dans une conversation `/p/<profil>/`, une commande dangereuse remonte au patron (`approval.request`, vérifié en E0a). Sur une carte, personne ne peut répondre : la commande devrait être refusée (`approvals.single_query_mode` ou `unattended_mode`, `deny` par défaut, `tools/approval_context.py`). À confirmer en E3 sur v0.22.5, où la carte est jouée par le gateway.
5. **La consigne de `SOUL.md`**, en dernier : une consigne n'est pas une garantie (plan, point A).

## Missions

Chaque mission a `id`, `title`, `schedule` (cron à 5 champs), `schedule_label` (dit au patron), `skills`, `instructions` et `result`. D7 reste ouverte : `instructions` se suffit à elle-même et sert telle quelle de corps de carte créée par Sam (a) ou de consigne d'une mission du profil (b), par exemple `hermes -p <p> cron create "<schedule>" "<instructions>" --name <id> --skill <skill> --deliver local`. Règles :

- Aucune mission n'est active sans l'accord du patron : elles sont proposées à la création.
- Au moins 30 minutes entre deux passages (idée de `bot-forge` : chaque passage est un appel payant). Celles du catalogue sont hebdomadaires ou mensuelles.
- `instructions` nomme chaque skill (« Utilise le skill xlsx… ») : les modèles gratuits n'invoquent pas un skill qu'on ne leur nomme pas (CLAUDE.md).

## Vérifier un changement

```bash
~/.hermes/hermes-agent/venv/bin/python3 -I -B scripts/check-roles.py
```

En lecture seule, avec un `HERMES_HOME` jetable et sans cache `.pyc`. Il vérifie : les clés et leurs types ; la fiche en 2 ou 3 phrases et la description en 1 ou 2 ; les marqueurs de `soul` et la présence de `kanban_complete`, `kanban_block`, `needs_input`, `capability`, `artifacts` et de l'empreinte ; que chaque skill existe dans l'Hermes local (livré ou optionnel) et n'est pas un skill d'envoi ; que chaque toolset existe et que les interdits obligatoires y sont ; `approvals.mode: manual` et, avec le vrai code d'Hermes, 46 commandes d'envoi bloquées et 19 commandes courantes laissées passer ; le plancher de 30 minutes ; les questions et le contexte ; 10 tests dont 3 ambigus ; les domaines disjoints et le même bloc `approvals.deny` partout. Il affiche l'empreinte de chaque fiche.

## Constats et questions ouvertes

- **Le `SOUL.md` d'un profil n'est pas protégé.** `security.protected_instruction_files` exempte le dossier d'Hermes (`_hermes_exempt_homes`, `tools/file_tools_write_guards.py`) : un agent peut réécrire son propre `SOUL.md` avec `write_file`, sans accord. La note 4 d'E0b disait l'inverse. À confirmer en E3 ; E4 peut comparer le fichier à celui qu'il a écrit.
- **Fin d'une carte avec un brouillon** : les fiches disent `kanban_complete` avec le fichier joint (le patron envoie lui-même, D3). Autre voie native : `kanban_request_review` avec `kanban.review_dispatch: false`, qui donne « Valider » (`complete`) et « Renvoyer » (`reopen-review --reason`), vérifiée en E0a (Q4b). À trancher en E8.
- **Skills réécrits par l'agent** : le toolset `skills` contient `skill_manage`. `skills.write_approval: true` mettrait ces écritures en attente. Non retenu ici : à décider en E4.
- **Le canvas** montre « Envoyer », « Inès a publié le post LinkedIn » et « Hugo a organisé ton agenda » : contraire à D3. Les fiches s'en tiennent à D3 ; à aligner en E1.
- **Aucun rôle n'a `llm-wiki`** : le cerveau reste à Sam (plan, point 6, à confirmer).
- `competitor-news-monitor` crée lui-même sa mission avec l'outil `cronjob`, ici retiré : la veille d'Inès est une mission du catalogue (D7).
- `image_gen` (Inès) ne marche qu'avec une clé d'images dans le profil.
- `hermes profile create --no-alias` évite d'écrire un lanceur `~/.local/bin/<profil>` (à décider en E4).
- Écritures qu'E4 ajoutera aux exceptions de CLAUDE.md, en plus de la liste du plan : `skills.disabled` et `hermes -p <p> skills install official/… --yes`.
