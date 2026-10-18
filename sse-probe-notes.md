# SSE Probe Notes — `/v1/responses` on Hermes v0.11.0

> Verified against Hermes v0.13.0 on 2026-05-10. SSE event shapes
> unchanged: `_handle_responses` still branches on `stream=True` at
> `~/.hermes/hermes-agent/gateway/platforms/api_server.py:1393` and
> emits the same `response.output_text.delta` / `response.output_item.{added,done}`
> sequence. v0.13 added `X-Hermes-Session-Key` as an opt-in header on
> the same endpoint (independent from `X-Hermes-Session-Id`); NotchNotch
> does not currently send it. Models cited below (`nemotron-3-super-120b-a12b:free`,
> `minimax/minimax-m2.7`) reflect the 2026-04-23 probe environment;
> available models on v0.13 are listed in `HermesConfig.availableModels`.

Empirical observations from probing `POST http://localhost:8642/v1/responses` with `stream: true` on **Hermes Agent v0.11.0 (2026.4.23)**. v0.10.0 does NOT stream this endpoint (returns plain JSON despite `stream: true`) — v0.11.0 is the floor.

All probes were made with the actually-running gateway process on localhost, NOT from reading docs. Source cross-reference: `~/.hermes/hermes-agent/gateway/platforms/api_server.py` (`_handle_responses` at line 1393 branches on `stream=True` into `_write_sse_responses` at line 1170).

## Content-Type signal

- `stream: true` + v0.11.0 → `Content-Type: text/event-stream`, `Transfer-Encoding: chunked`, `X-Hermes-Session-Id: <uuid>`
- `stream: true` + v0.10.0 or older → `Content-Type: application/json`, full JSON body (silent fallback)
- Validation errors (missing `input`, etc.) → HTTP 4xx + `Content-Type: application/json` + `{"error": {"message": "...", "type": "invalid_request_error"}}` — NEVER SSE

Client MUST check `Content-Type` on the response before iterating as SSE. If it's `application/json`, parse the body once and emit a single synthetic `.completed`.

## Event framing

- `event: <name>` line, one or more `data: <json>` lines, blank line terminates the event
- Each payload carries `sequence_number` (int, monotonic from 0). Not strictly needed client-side since the stream is ordered, but it's there.
- `data` JSON always has a `type` field matching the event name
- No `id:` / `retry:` / comment lines observed

## Event order — text-only request

```
response.created
response.output_item.added      { item.type = "message",  item.status = "in_progress" }
response.output_text.delta      (1 or more)
response.output_text.done
response.output_item.done       { item.type = "message",  item.status = "completed"   }
response.completed
```

**Delta granularity depends on provider**:

- `minimax/minimax-m2.7` (currently configured) → true chunk-level streaming. 6 deltas for ~84-char haiku, 41 deltas for a ~300-char tool-follow-up response. Typewriter UX will work nicely.
- `nvidia/nemotron-3-super-120b-a12b:free` (earlier probe) → **single** `response.output_text.delta` carrying the whole assistant text. The server has a fallback at `api_server.py:1478-1480` that emits a single delta if the upstream provider didn't produce any incremental deltas.

For the client this is a non-issue — append-deltas works identically whether it's 1 chunk or 100. Client should NOT assume `delta` is a single token; it's an opaque string chunk that can be anything from a single character to the full response.

## Event order — request with tool call (e.g. `terminal ls`)

```
response.created
response.output_item.added      { item.type = "function_call",        item.status = "in_progress" }
response.output_item.done       { item.type = "function_call",        item.status = "completed"   }
response.output_item.added      { item.type = "function_call_output", item.status = "completed"   }
response.output_item.done       { item.type = "function_call_output", item.status = "completed"   }
response.output_item.added      { item.type = "message",              item.status = "in_progress" }
response.output_text.delta
response.output_text.done
response.output_item.done       { item.type = "message",              item.status = "completed"   }
response.completed
```

Key: `function_call.added` carries the full `arguments` string already — it's NOT a partial payload that accumulates. Same for `function_call.done` (identical arguments). So client can react on `.added` alone and ignore `.done` for function_call if we just want the minimal streaming visibility. Same duplication applies to `function_call_output`: `.added` and `.done` carry identical payloads.

## `function_call` item shape

```json
{
  "id": "fc_2ca8e5102bbf4e04bcc39e48",
  "type": "function_call",
  "status": "in_progress" | "completed",
  "name": "terminal",
  "call_id": "chatcmpl-tool-836e973d8360fa8f",
  "arguments": "{\"command\": \"ls /tmp | head -5\"}"
}
```

- `id` — server-generated per item, `fc_` prefix
- `call_id` — provider-assigned (OpenAI/OpenRouter); matches the corresponding `function_call_output.call_id`
- `arguments` — **already a JSON string**, not a dict. Client should pass to a JSON parser if it wants structured fields, or just display as-is (truncated to N chars).

## `function_call_output` item shape

```json
{
  "id": "fco_13c5e9efdf9641d38be83612",
  "type": "function_call_output",
  "call_id": "chatcmpl-tool-836e973d8360fa8f",
  "output": [
    {
      "type": "input_text",
      "text": "{\"output\": \"...\", \"exit_code\": 0, \"error\": null}"
    }
  ],
  "status": "completed"
}
```

- `output` is an **array** of content parts, not a single string. Each part has `type` (`input_text` observed) and `text`.
- The `text` value is itself a JSON-serialised string of whatever the tool returned (here a `{output, exit_code, error}` dict). Display pattern: take first N chars of the joined text values, or parse if you care about structured fields.

## `response.completed` terminal payload

```json
{
  "type": "response.completed",
  "response": {
    "id": "resp_02809c41af39446a9f4833e62a6c",
    "object": "response",
    "status": "completed",
    "created_at": 1776987553,
    "model": "hermes-agent",
    "output": [ /* full ordered list of all emitted items */ ],
    "usage": {
      "input_tokens": 31790,
      "output_tokens": 293,
      "total_tokens": 32083
    }
  },
  "sequence_number": N
}
```

- `usage.input_tokens` / `usage.output_tokens` — same key names as the non-streaming path. Not `prompt_tokens` / `completion_tokens`.
- `response.output` in the terminal payload is the authoritative final state (same shape as the non-streaming response). Client can use it as the source-of-truth for reconciliation after the stream ends.
- `response.output[-1]` is always a `message` item with the final assistant text; tool items precede it in order of execution.

## `response.failed`

Not triggered in any of my probes (couldn't reproduce mid-stream failure easily). Per source (`api_server.py:1528-1540`), on agent error the stream emits:

```
event: response.failed
data: { "type": "response.failed", "response": { status: "failed", output: [...], error: { message, type: "server_error" }, usage: {...} } }
```

Still HTTP 200 + `text/event-stream`. Client must surface the `response.error.message`.

## Conversation chaining

`conversation: "<name>"` in body → server resolves to the latest `response_id` stored under that conversation name (per `api_server.py:1422-1424`) and uses it as `previous_response_id`. My probe sent `"notchnotch-sse-probe-text-v2"` twice: the second call correctly remembered the haiku from the first. Same mechanism as the non-streaming path. No change to our existing `HermesClient.conversationId` logic required.

## Unknown / undocumented events

None observed. No heartbeats, no `id:` lines, no retries. Plan mentions `response.reasoning_summary_text.delta` for thinking content — not observed on this model (nemotron is not a reasoning model). If/when we switch to a reasoning-capable model, we should handle it; for now the client should just log-and-ignore unknown event names (safe default). The plan already specified this.

## Headers sent vs. headers required

- `Content-Type: application/json` — required
- `Accept: text/event-stream` — NOT required by Hermes (I tested omitting it; server still streams correctly when `stream: true` is in the body). We'll send it anyway for good-hygiene.
- `X-Hermes-Session-Id` — informational; Hermes returns its own if we don't send one. Our client already sets `notchnotch-<uuid>`.
- `Idempotency-Key` — supported in source but we don't use it. No change.

## Deviations from plan's spec

Minor:

1. Plan says to react on `response.output_item.added` for `function_call` as "started" and on `response.output_item.done` for `function_call_output` as "completed". Empirically `function_call_output` comes via `response.output_item.added` (status already `completed`), and its `.done` is a duplicate. Client-side rule: `function_call.added` → started, `function_call_output.added` → completed. Ignore both `.done` variants for minimal logic.

2. Plan mentions `response.reasoning_summary_text.delta` for thinking deltas. Not observed on the configured model. Keep the handler stub but don't rely on it in tests.

3. Delta granularity varies by provider — minimax gives true chunk streaming, free-tier nemotron gives a single big delta. Client just appends; both cases work.

4. `response.output_text.delta` carries a `"logprobs": []` field we don't need. Ignore.

5. Every event payload has `"sequence_number"` — plan didn't mention it. Just pass through.

## Recap — minimal client state machine

| Event | Client action |
|---|---|
| `response.created` | Reset content accumulator (optional, can also use the one already zeroed) |
| `response.output_item.added` with `item.type == "function_call"` | Fire `toolCallStarted(id=item.call_id, name=item.name, args=item.arguments)` |
| `response.output_item.added` with `item.type == "function_call_output"` | Fire `toolCallCompleted(id=item.call_id, result=join(item.output[*].text))` |
| `response.output_item.added` with `item.type == "message"` | No-op (text delta arrives next) |
| `response.output_text.delta` | Append `data.delta` to content accumulator; fire `.textDelta(delta)` |
| `response.output_text.done` | No-op (already have all deltas). Optionally reconcile accumulator against `data.text`. |
| `response.output_item.done` | No-op (payload is redundant with earlier events) |
| `response.completed` | Extract `usage.input_tokens` / `usage.output_tokens`; prefer `response.output[*]` as source-of-truth for final reconciliation; fire `.completed(pt, ct)`; break loop |
| `response.failed` | Fire `.failed(error.message)`; throw |
| unknown event | Log-and-ignore |

## Probe files (for reference)

Kept in `/tmp/` on my machine (not committed):

- `/tmp/sse-probe-text.txt` — simple haiku stream (nemotron, single delta)
- `/tmp/sse-probe-tool.txt` — `terminal ls /tmp` tool call (nemotron)
- `/tmp/sse-probe-chain.txt` — conversation continuation (proves chaining works)
- `/tmp/sse-probe-err2.txt` — missing `input` field (HTTP 400 JSON)
- `/tmp/sse-probe-minimax-text.txt` — haiku stream with minimax (6 deltas, real streaming)
- `/tmp/sse-probe-minimax-tool.txt` — tool call with minimax (3 items, 41 text deltas)
- `/tmp/sse-probe-text-headers.txt`, `/tmp/sse-probe-err2-headers.txt`, `/tmp/sse-probe-minimax-headers.txt` — headers for the above

## Probe Hermes v0.21.6 (2026-10-11)

Session H0, lecture seule côté NotchNotch. Aucune ligne de Swift modifiée.

**Environnement mesuré**

- Avant : Hermes **v0.21.0** (pas v0.14) depuis le 31/08. Le gateway LaunchAgent tournait mais `:8642` était **fermé** : sans `API_SERVER_KEY` d'au moins 16 caractères, la plateforme `api_server` n'est pas enrôlée (`gateway/config.py:877`). NotchNotch et le Clipper étaient donc déjà coupés. Le `state.db` ne contient aucune session NotchNotch ni Telegram sur les 60 derniers jours.
- `hermes update` (programme v0.21.0, sans notion de canal) a tiré `main` : **v0.21.6+730.g97a9ae8**, après `rc.11-v0.21.7`, et le canal `stable` est maintenant enregistré. Le canal stable refuse de rétrograder (*« this checkout is newer and waits for the next release »*). Avec l'accord de Jérémie, on a gardé `main`. La lecture de code des probes 7 et 10 à 14 a été faite sur le tag `v0.21.6` ; les probes en direct (1 à 6, 8, 9) tournent sur `97a9ae8`. `/health` répond `"version": "0.21.6"`.
- Modèle par défaut `minimax/MiniMax-M2.5` : **HTTP 402, crédit épuisé**. Les probes agent passent `model` + `provider` par requête (`nvidia/nemotron-3-super-120b-a12b:free` via `openrouter`), sans modifier la config.
- Sauvegarde : `~/.hermes.backup-v014-20261011` (6 Go, `quick_check` OK sur `state.db` et `response_store.db`). Elle contient la **v0.21.0** ; le nom suit le brief.
- Écritures faites hors dépôt pendant la session :
  - `API_SERVER_KEY` (48 caractères) ajoutée à `~/.hermes/.env`, puis `hermes gateway restart` ;
  - la mise à jour a migré la config (format v23 → v50) et réécrit le plist LaunchAgent (voir « Hors probes ») ;
  - le probe 6 a fait créer un job cron « 5m ping » par l'agent, supprimé ensuite via `DELETE /api/jobs/314bc97623f1` (on revient aux 7 jobs d'origine) ;
  - un verrou de modèle reste posé sur la session de probe `b1da78bc…` (sans effet ailleurs) ;
  - le dossier de test du probe 4 a été supprimé par l'agent après approbation.

**Numérotation des sessions** : le plan H1–H15 n'est pas dans le dépôt. Seul « H1 = clé API » vient du brief ; les autres numéros ci-dessous sont une **proposition par thème**, à recaler sur ton plan.

### Tableau

| # | Probe | Résultat | Impact NotchNotch | Session |
|---|---|---|---|---|
| 1 | Auth | `GET /health` et `/v1/health` : 200 sans clé, `{"status":"ok","platform":"hermes-agent","version":"0.21.6"}`. `POST /v1/responses` et `GET /api/jobs` sans clé ou avec une mauvaise clé : **401** `{"error":{"message":"Invalid gateway API key (API_SERVER_KEY)","type":"gateway_auth_error","code":"gateway_auth_failed"}}`. Avec `Authorization: Bearer <clé>` : 200. | Tout est en 401 sauf `/health` : chat, `sendCompletion`, `generateTitle`, mémoire, REST cron, pipeline brain, Clipper. `/health` expose maintenant la version (CLAUDE.md dit le contraire). | H1 |
| 2 | SSE texte | `text/event-stream`. Séquence inchangée, plus un nouvel événement `hermes.status` `{kind: warn\|lifecycle, text}`. Une erreur fournisseur (402) ne donne **pas** `response.failed` : on reçoit `response.completed` avec le message d'erreur comme texte assistant et `usage` à 0. `conversation` chaîne toujours. **`X-Hermes-Session-Id` envoyé par le client est ignoré** sur `/v1/responses` : ordre « chaîne `conversation`/`previous_response_id` › `X-Hermes-Session-Key` › `uuid4` » (`gateway/platforms/api_server_openai_routes.py:1120`). L'ID réel revient dans l'en-tête de réponse. | Le parseur SSE tient (`hermes.status` est loggé et ignoré). Cassé : `notchnotch-<uuid>` n'est plus l'ID de la ligne `state.db`, donc `TitleStore`, la session active de l'historique et la reprise d'une ancienne conversation sont faux. Les erreurs fournisseur s'affichent comme une réponse normale. | H2 |
| 3 | Reasoning + outils | Le raisonnement passe par le canal dédié `response.reasoning_summary_text.delta` (clé `delta`), encadré par `output_item.added {type: reasoning}` et les nouveaux `reasoning_summary_part.added/done` et `reasoning_summary_text.done`. Aucun `<think>` inline (nemotron), et plusieurs blocs de raisonnement par tour. Outils : formes inchangées (`arguments` est une chaîne, `output[] = {type: input_text, text}`). L'item `reasoning` final porte `summary[].text`. | `SSEParser` et `ThinkTagSplitter` couvrent. Bug : `parseOutput` lit `item["text"]` pour `reasoning` (`HermesClient.swift:516`), donc le raisonnement est perdu sur le chemin JSON non-stream, et écrasé au lieu d'être concaténé. Nouveaux noms d'outils vus : `tool_search`, `tool_describe`, `cronjob_manage` (à ajouter à `verbMapping`). | H2 |
| 4 | Approbations | Config : `approvals.mode: manual`, `timeout: 60`, `cron_mode: deny`. Sur `/v1/responses`, la commande dangereuse est **bloquée immédiatement**, sans événement ni attente : `api_server` est classé « sans surveillance » (`tools/approval_context.py:135`). Le message renvoyé dit « set approvals.unattended_mode: approve ». Sur `/v1/runs`, `approval.request` arrive en ~4 s (clés : `command`, `description`, `pattern_key(s)`, `choices: [once, session, always, deny]`, `allow_session`, `allow_permanent`, `request_id`). `POST /v1/runs/{id}/approval {"choice":"once"}` répond 200 `{"object":"hermes.run.approval_response","resolved":1}`, puis `approval.responded` et la commande s'exécute. | Via `/v1/responses`, NotchNotch ne pourra jamais faire approuver quoi que ce soit, et le sélecteur `approvals.mode` n'a aucun effet sur le chat. Pour approuver, il faut passer le chat sur `/v1/runs` + `GET /v1/runs/{id}/events`, dont le vocabulaire diffère (`message.delta`, `reasoning.available`, `tool.started/completed`, `run.completed`) : trames `data:` + `id:`, sans `event:`. | H3 |
| 5 | Modèle par requête | `model` + `provider` dans le corps (ou `provider/model` préfixé) sont honorés : `response.model` = modèle réellement servi. `"hermes-agent"` est un alias qui renvoie au défaut de la config. `GET /api/model/options` renvoie `{model, provider, providers[52]{models}}`, alors que `/v1/models` ne liste que `hermes-agent`. `POST /api/sessions/{id}/model` répond 200 `hermes.session.model_lock` et persiste le verrou, mais celui-ci n'est lu que par `/api/sessions/{id}/chat(/stream)` (`api_server.py:3405`, `:4243`), **pas par `/v1/responses`** : vérifié, le tour suivant est reparti chez MiniMax. | NotchNotch peut choisir le modèle par requête sans écrire `config.yaml`. `/api/model/options` peut remplacer la liste codée en dur de `HermesConfig.availableModels`. | H4 |
| 6 | Slash | `/goal test probe` et `/loop 5m ping` sont traités comme **du texte**. `/goal` : simple réponse du modèle, aucun objectif créé. `/loop` : le modèle a créé un vrai cron via `cronjob_manage` (supprimé ensuite). Aucune route HTTP ne gère les commandes slash : elles ne passent que par les messageries (`gateway/slash_commands_goals.py`) et par le RPC `tui_gateway`. | `/goal` n'est **pas débloqué** côté HTTP (la note mémoire `project_hermes_goals_api_gap` reste vraie). Risque : un « /loop » tapé dans NotchNotch crée des jobs. | H5 |
| 7 | RPC Desktop | JSON-RPC ligne par ligne, sur stdio (TUI) et sur WebSocket `/api/ws` (`hermes_cli/web_routers/chat_ws.py:701`). Le WebSocket est servi par `hermes dashboard` / `serve`, un **autre process** que le gateway, avec un port choisi au lancement (Desktop utilise `--port 0`). Auth en loopback : `?token=<session token>` (`HERMES_DASHBOARD_SESSION_TOKEN`, sinon aléatoire à chaque démarrage, `hermes_cli/web_server.py:383`) plus contrôle Host/Origin ; en mode protégé, un ticket. Méthodes : `slash.exec {session_id, command}`, `command.dispatch {name, arg, session_id}`, `wake.start`, `wake.feed` (`tui_gateway/contracts/`). Le serveur envoie aussi ses propres requêtes au client (`approval`, `clarify`, `secret`…) une fois `client.capabilities {server_requests: true}` déclaré. Aucun dashboard ne tourne ici, mais `/Applications/Hermes.app` existe. | Branchable : NotchNotch lance `hermes dashboard --port <p>` avec un token qu'il génère, puis ouvre un client WebSocket JSON-RPC. Ça débloquerait `/goal` (`slash.exec`) et les approbations natives. Le prix : un 2e process à superviser, un protocole riche (requêtes serveur→client), des contrats Pydantic→TS qui bougent vite, et un recouvrement avec Hermes Desktop. | H6 |
| 8 | Missions | `jobs.json` = `{jobs, updated_at}`, 29 clés par job. Nouveaux champs : `base_url`, `created_at`, `enabled_toolsets`, `failure_streak`, `fire_claim`, `last_delivery_error`, `last_dispatch`, `model`, `paused_at`, `paused_reason`, `provider`, `script`, `skill`, `skills`, `workdir`. **Aucun champ de `CronJob` renommé ni disparu, types conformes → le décodage actuel passe.** `schedule.kind` ∈ {`cron`, `interval`}. `GET /api/jobs` renvoie les mêmes clés plus `latest_execution {status, error, started_at, finished_at, …}`. Sorties : toujours `## Response` ; en cas d'échec, `## Error` et un titre suffixé « (FAILED) ». Whitelist PATCH étendue à `skills`, `skill`, `repeat`. | `CronStore` OK. REST cron en 401 sans clé (H1). `latest_execution.error` est le meilleur signal d'échec pour les toasts. 6 jobs sur 7 sont en `last_status: error` (MiniMax 402 ou hors ligne). | H1 + H7 |
| 9 | state.db | `schema_version` 31. Colonnes ajoutées : `sessions.{created_source, compression_overload_streak, transport_profile, auto_archived}` et `messages.{display_identity, display_order, message_uid, absorbed_message_uids, tool_call_uids, tool_call_uid}`. Rien de supprimé. Les 4 requêtes Swift passent en `-readonly` : détection Telegram OK ; `loadRecentSessions` renvoie 5 lignes, toutes `api_server` (les probes du jour) ; `messagesForSession` OK (0 `content` NULL, 0 ligne inactive/compactée) ; métriques d'activité : 2 165 sessions sur 61 jours, coût **0.0** (1 154 sessions à `estimated_cost_usd = 0`, `cost_status = unknown`). | Rien de cassé côté SQL. Le coût affiche « 0 $ » au lieu de « — », parce qu'une valeur estimée à 0 compte comme connue. L'historique est vide simplement parce que NotchNotch est déconnecté depuis des semaines. Hermes propose `hermes sessions optimize-storage` (~0,4 Go). | H8 |
| 10 | Mémoire | `MEMORY.md` (1 922 o) et `USER.md` (511 o) sont présents, avec le séparateur `\n§\n` (`ENTRY_DELIMITER`, `tools/memory_tool_store.py:25`). `memory.write_approval: false` (défaut ; à `true`, les écritures directes demandent une approbation et celles en arrière-plan passent par `/memory pending\|approve\|reject`). **Local uniquement : non.** L'outil `memory` n'accepte que `action ∈ {add, replace, remove, batch}` × `target ∈ {memory, user}`, et tout est injecté dans le prompt (`tools/memory_tool.py:375-390`). La seule exclusion possible est par fichier entier (`memory_enabled`, `user_profile_enabled`). Hindsight (fournisseur actif) a déménagé dans `~/.hermes/plugins/hindsight/` ; `hermes-agent/plugins/memory/` ne contient plus que `byterover`, `retaindb` et un dossier `hindsight/` vide. | `BrainViewModel` OK. `HermesMemoryConfig.scanInstalledPlugins` ne voit plus Hindsight ni les fournisseurs installés depuis le catalogue, donc le sélecteur est faux. | H9 |
| 11 | Routage fournisseurs | `provider_routing.{only, ignore, order, sort, require_parameters, data_collection}` devient l'objet `provider` du corps OpenRouter (`plugins/model-providers/openrouter/__init__.py:133-140`, construit dans `agent/chat_completion_helpers.py:469-487`). **Aucun drapeau `zdr`** (seulement dans un test). Mais `api_server._create_agent` (`gateway/platforms/api_server.py:2389`) **ne transmet pas** les valeurs globales `provider_routing.*` : seules les messageries le font (`gateway/run_turn_runner.py:1123`). `/v1/responses` ne reçoit que `provider_routing.models.<id>`, lu directement dans la config. | Pour garantir `only` / `data_collection` dans NotchNotch, il faut écrire sous `provider_routing.models.<model_id>`, pas au niveau global. Le ZDR n'est pas supporté : à demander en amont, ou à approcher via `only`. | H10 |
| 12 | Secrets via Trousseau | Source `secrets.command` (`agent/secret_sources/command.py`, doc `website/docs/user-guide/secrets/command.md`). Un script est lancé **une fois au démarrage** via `/bin/sh -c` ; il doit imprimer des lignes `KEY=VALUE` (timeout 3 s, stderr jeté) ; `.env` garde la priorité sauf avec `override_existing: true`. Ça couvre n'importe quelle variable d'env, donc `API_SERVER_KEY` et les clés fournisseurs. Config : `secrets: {command: {enabled: true, command: "~/.hermes/bin/keychain-env.sh", override_existing: true}}`, avec un script qui fait `printf 'API_SERVER_KEY=%s\n' "$(security find-generic-password -s <service> -a API_SERVER_KEY -w)"`. Alternative par fournisseur : `providers.<name>.key_cmd` (`agent/command_token_source.py`). | **Faisable.** NotchNotch lirait le même item via `SecItemCopyMatching`. Pièges : le script doit être non interactif (l'ACL de l'item doit autoriser `/usr/bin/security` et NotchNotch ; NotchNotch est signé ad hoc, donc ACL liée au cdhash et invite à chaque rebuild) ; une rotation impose un redémarrage du gateway ; il faut retirer les clés de `.env`. | H11 |
| 13 | Contexte long | Config : `compression.enabled: true`, `threshold: 0.75` (défaut du code : 0.50), `target_ratio: 0.2`, `protect_last_n: 20`, `tail_mode: lean`, `hygiene_hard_message_limit: 400`. Autres défauts du code : `checkpoint_required: false`, `progress_notices: false`, `threshold_tokens: None`, `min_tail_user_messages: 1`, `max_attempts: 3`, `proactive_prune_tokens: 0`. `compression.summary_base_url` n'existe plus. | Rien à changer pour « une seule conversation continue ». `HermesConfig.probeCompressionEndpoint` est devenu du code mort (clé absente → `.notConfigured`). | H12 |
| 14 | Contrôle du Mac | `cua-driver` **0.21.0**, épinglé par le gestionnaire de paquets de Hermes (`~/.hermes/tools/cua-driver-0.21.0-darwin-arm64/`, symlink `~/.local/bin/cua-driver`) ; `HERMES_CUA_DRIVER_VERSION` n'est plus utilisé. **`hermes computer-use install` propage enfin son code de retour** : `return 0 if install_cua_driver(...) else 1` (`hermes_cli/subcommands/computer_use.py:31`). Nouveau `hermes computer-use permissions status --json` → `{accessibility, screen_recording, ready, installed, version, can_grant, checks[]}`, exit 0 si `ready`. Ici : `accessibility` et `screen_recording` à `null`, `ready: false`, exit 1. `permissions grant` existe aussi. | La double vérification du PATH dans `ComputerUseService` reste juste mais devient redondante. `permissions status --json` peut remplacer « l'acte de foi » `computerUsePermissionsConfirmed`. | H13 |

**Hors probes, mais à connaître**

- **LaunchAgent repris par Hermes.** `hermes update` a réécrit `~/Library/LaunchAgents/ai.hermes.gateway.plist` (même label) : un wrapper `osascript` JXA lance `~/.hermes/hermes-agent/.hermes/bin/hermes … gateway run --external-supervisor` sur un Python 3.14.7 embarqué (`~/.hermes/tools/`). `HermesGatewayLauncher.install()` compare son modèle octet par octet et **écraserait le plist de Hermes** (repair toast, Settings → Installer). → H1 / H14.
- `hermes init` **n'existe plus** : `OnboardingViewModel.swift:164` appelle une commande inexistante, et l'erreur est avalée par `try?`. `scripts/install.sh` existe toujours sur `main`. Le venv 3.11 et les imports `browse_skills` / `inspect_skill` de `SkillsHubClient` fonctionnent.
- `hermes status --short` n'existe pas (il y a `--full`). L'avertissement « previous `hermes update` … did not restart » reste affiché même après `hermes gateway restart` (marqueur périmé).
- `~/.hermes/.env` contient **8 lignes `OPENROUTER_API_KEY=`**. `writeRawEnv` n'est peut-être pas idempotent → H1.
- Migration de config pendant la mise à jour, entre autres : `display.personality: none`, `delegation.max_iterations: 250`, `display.background_process_notifications: concise`, `security.tirith_*` supprimé.

### Cassé aujourd'hui (NotchNotch tel quel sur v0.21.6+)

1. **Tout ce qui passe par `:8642` sauf `/health`** est en 401 : chat, sauvegardes brain, titres, édition/suppression mémoire, pause/reprise/édition de routines, pipeline brain, extension Clipper. Sans la clé ajoutée pendant H0, le port est même fermé.
2. **Boot et onboarding** : `ensureApiServerEnvVars` et `ensureLaunchAgentAndAwaitHealth` n'écrivent pas `API_SERVER_KEY`. Une install fraîche laisse donc `:8642` fermé, et le toast « Hermes ne répond pas » lance une réparation qui ne règle rien et **écrase le plist de Hermes**.
3. **Identité de session** : `X-Hermes-Session-Id` est ignoré, ce qui rend incohérents `TitleStore`, la session active de l'historique et la reprise d'une conversation passée.
4. **Approbations** : impossibles via `/v1/responses` (blocage sec), et le sélecteur `approvals.mode` est sans effet sur le chat NotchNotch.
5. **Erreurs fournisseur** (402, hors ligne) : rendues comme une réponse `completed`, donc pas de toast d'erreur, juste une bulle normale contenant le texte d'erreur.
6. **Sélecteur de fournisseur mémoire** : Hindsight, le fournisseur actif, est absent du scan.
7. **`hermes init` absent** : la branche d'onboarding « config.yaml manquant » ne fait rien.
8. **`parseOutput`** perd le raisonnement sur le chemin JSON (`summary[].text`).

Fonctionne toujours : parsing SSE, décodage cron, les 4 requêtes SQL, lecture de `MEMORY.md` / `USER.md`, install `computer-use`.

### Tailles revues

Le contenu prévu pour H2 et H3 n'étant pas dans le brief, les estimations ci-dessous partent de l'hypothèse de contenu indiquée.

- **H1 (clé API) : plus grosse que prévu.** Ce n'est pas qu'un en-tête. (a) `Bearer` sur les 5 points d'appel de `HermesClient` et dans le Clipper. (b) Générer et écrire la clé au boot et à l'onboarding, sinon le port reste fermé. (c) Choisir où la stocker (`.env` aujourd'hui, Trousseau possible : voir probe 12). (d) Régler le conflit LaunchAgent : Hermes possède maintenant `ai.hermes.gateway.plist`. Je suggère de garder (a) à (c) dans H1 et de sortir (d) en H1b.
- **H2 (session + SSE) : identique, voire un peu plus grosse.** Le parseur SSE tient. Mais il faut repenser l'identité de session : lire l'ID renvoyé par le serveur, envisager `X-Hermes-Session-Key`, re-clé `TitleStore` et l'historique. S'y ajoutent `hermes.status` → toasts, les erreurs fournisseur reçues en `completed`, et le correctif `parseOutput`.
- **H3 (approbations) : plus grosse, à scinder.** Rien n'est possible sur `/v1/responses`. **H3a** : passer le transport du chat sur `/v1/runs` + `/events` (nouveau vocabulaire, retry, continuité de conversation à vérifier). **H3b** : l'interface d'approbation (`approval.request` → `choices` → `POST /approval`). Une alternative au rabais existe, `approvals.unattended_mode: approve`, mais c'est une décision de sécurité.

### Questions ouvertes

1. `/v1/runs` : comment se fait la continuité de conversation (`session_id`, `previous_response_id`, persistance dans `response_store`) ? Non testé. C'est le préalable à H3a.
2. `memory.write_approval: true` sur `api_server` : est-ce aussi bloqué comme « sans surveillance » ? Non testé.
3. Rester sur `main` ou repasser sur une stable propre quand v0.21.7 sortira ? (`hermes update` attend désormais la prochaine stable.)
4. Hermes Desktop (`/Applications/Hermes.app` + dashboard `/api/ws`) : NotchNotch doit-il le compléter, s'y brancher (probe 7) ou s'en démarquer ?
5. Les 8 doublons `OPENROUTER_API_KEY` dans `.env` : d'où viennent-ils, et laquelle gagne ?
6. `permissions status --json` renvoie `null` pour les droits TCC : faut-il que le daemon `cua-driver` tourne ?
7. MiniMax en 402 : recharger, ou changer le modèle par défaut ? C'est ta décision ; aujourd'hui, toutes les routines échouent.

## Probe /v1/chat/completions (H3, 2026-10-11)

Curl sur v0.21.6 (`main` @ `97a9ae8`, `/health` → `0.21.6`), modèle par défaut `nvidia/nemotron-3.5-lightning:free`, clé en Bearer. Code lu : `gateway/platforms/api_server_openai_routes.py` (`_handle_chat_completions`, `_write_sse_chat_completion`, `_register_stream_approval`). Lignes `notchnotch-h3probe-*` laissées dans `state.db`.

| Point | Résultat |
|---|---|
| Continuité par ID | `X-Hermes-Session-Id: notchnotch-h3probe-…` inconnu → ligne créée avec `id = session_key =` cette valeur ; « choisis un nombre au hasard » (739) puis « quel nombre as-tu dit ? » → 739. |
| Clé seule | `X-Hermes-Session-Key` sans ID : une nouvelle ligne `api-…` par tour, le 2e tour ne connaît pas le 1er. |
| Reprise H2a | ID = ligne `b858b6a4…` (clé `notchnotch-h2a-f9019…`, créée sur `/v1/responses`) → le contexte (« citron ») est là, le tour s'ajoute à la même ligne. |
| Flux | 1er chunk `delta.role`, puis `delta.reasoning_content` (≈300 chunks sur un tour court), `delta.content`, frames nommées `hermes.status` et `hermes.tool.progress {tool, emoji, label, toolCallId, status}` (vrais noms d'outils vus : `execute_code`, `terminal` ; `label` = aperçu Hermes, la commande brute pour `terminal`). Fin : `finish_reason` + `usage {prompt_tokens, completion_tokens, total_tokens}`, puis `data: [DONE]`. `: keepalive` pendant les silences. |
| `tool_call` | Le champ `tool` est le nom appelé par le modèle : via le pont `tool_call`, il vaut `tool_call` et `label` décrit l'outil enveloppé (`_preview_bridge_call`). NotchNotch garde le verbe par défaut et n'affiche pas d'aperçu. |
| 402 MiniMax | `hermes.status` `warn` (titre auxiliaire) + `lifecycle` ❌, texte de facturation en `content`, puis `finish_reason: "error"`, `error {message: "HTTP 402: insufficient balance (1008)", type: agent_error}`, `hermes {failed: true, …}`, usage à 0. Un plantage en plein flux envoie `finish_reason: "error"` sans `error` (code, non déclenché). |
| Approbation | `rm -rf /tmp/nn-h3probe-dir` : `hermes.tool.progress` running (`terminal`), puis `approval.request {command, description: "delete in root path", choices: [once, session, always, deny], run_id: chatcmpl-…, request_id, session_id}`. `POST /v1/runs/{run_id}/approval {"choice":"deny","request_id"}` → 200 `resolved: 1` ; 2e POST → 409 `approval_not_pending`. Dossier intact, la réponse dit que la commande a été bloquée. Sans réponse : refus au bout de `approvals.timeout` (60 s), dossier intact. Pas d'`approval.responded`. Après la fin du tour, la route répond 409 `approval_not_active` (lu dans le code, non déclenché). |
| Arrêt | `curl -m 8` coupé en plein flux → `gateway.log` : « SSE client disconnected; interrupted agent task chatcmpl-… ». |
| Retry | Après une coupure, le même message renvoyé avec le même ID **duplique le message utilisateur** : Hermes a déjà enregistré le tour coupé (user + assistant partiel), puis ajoute user + assistant vide + assistant. Non contourné (limite connue du retry, comme sur `/v1/responses`). |

## Probe Hermes v0.22.2 (2026-10-18)

Lecture seule. Aucune ligne de Swift modifiée, rien exécuté côté Hermes : pas de `hermes update`, pas de changement de canal, pas de curl sur `:8642`. Toutes les conclusions viennent du code (aucun probe en direct) : elles restent à confirmer au curl après la mise à jour.

**Méthode**

- Install locale : `main` @ `97a9ae8` (`git describe` : `rc.11-v0.21.7-55-g97a9ae8ee5`), `install-stamp.json` `baseVersion: 0.21.6`, `/health` → `0.21.6` (H0).
- Notes de version : `gh api repos/NousResearch/hermes-agent/releases/tags/v0.22.{0,1,2}`.
- Code : clones partiels (sans blobs) dans le scratchpad du tag `v0.22.2` (`d923a5e`), de `v0.22.1` (`297552a`) et de `main` (`9e01b44`, 18/10), comparés blob par blob avec l'arbre local (`git ls-tree -r`). Les preuves `fichier:ligne` ci-dessous sont au tag `v0.22.2` sauf mention contraire.

**Ce que sont vraiment ces trois tags**

- **v0.22.0** (14/10) = install locale + 803 commits. Ses notes couvrent tout depuis v0.21.0 (v0.21.1 à v0.21.7 compris) : la plupart des nouveautés listées sont **déjà dans l'install locale** (canaux, `hermes pm`, outils renommés, fournisseurs mémoire en plugins, `sessions.auto_prune`, gateway unique pour tous les profils).
- **v0.22.1** (15/10 00h) a été construite **par erreur depuis `main`** (`297552a`) et a embarqué le travail « canonical » non publié : `gateway/session_authority.py`, `hermes_state_runtime.py`, `hermes_cli/dashboard_auth/native_http.py`, 809fec15 (« Refuse /v1/runs on a natively owned session with a bounded 409 », 09/09) et 75764b2a (« Authenticate native HTTP through private daemon grants », 08/09). Ces deux commits viennent d'une longue branche partie de `b2aa855` : ils ne sont **pas** dans l'install locale.
- **v0.22.2** (15/10 08h) : le commit de release `d923a5e` garde **exactement l'arbre de `release/0.22.1`** et ne cite v0.22.1 que comme parent (« Never merge this branch into main. Git would read it as reverting every change main made after 297552a9d6 »). Résultat : l'historique de v0.22.2 contient 809fec15 et 75764b2a, **mais pas leur code** (`gh api compare` dit « ahead » : il ment ici, il faut lire les fichiers). Le travail « canonical » partira avec v0.23.0, et il est déjà sur `main`.
- Écart local → v0.22.2 : 819 fichiers modifiés, 450 ajoutés, 65 supprimés sur 18 605. **Identiques octet pour octet** : `gateway/platforms/api_server*.py` (les 10 fichiers), `gateway/config.py`, `hermes_cli/gateway.py`, tout `cron/`, `tools/approval.py`, `tools/registry.py`, `hermes_cli/version_info.py`, le schéma `state.db`.

### Tableau

| # | Sujet | Constat | Impact NotchNotch | Session |
|---|---|---|---|---|
| 1 | Auth Bearer, ouverture de `:8642` | ✅ Fichiers identiques au local. 401 `gateway_auth_failed` sans clé (`gateway/platforms/api_server.py:1556`), adaptateur enrôlé seulement avec une clé de 16 caractères ou plus (`gateway/config.py:545-553`). | Rien à changer : `ensureApiServerEnv()` et le Bearer sur tous les appels sauf `/health` restent valables. | — |
| 2 | `/health` et sa version | ✅ `{"status":"ok","platform":"hermes-agent","version": _hermes_version()}` (`api_server.py:2427`), version lue dans `install-stamp.json` via `version_info.base_version` (`api_server.py:209-212`). Après mise à jour, le stamp devrait dire `0.22.2` (déduit, non mesuré). ⚠️ Doc : au tag `v0.22.2`, `pyproject.toml` dit toujours `version = "0.0.0"` et `hermes_cli/__init__.py` n'a plus de `__version__` littéral (attribut paresseux lu dans le stamp, l. 5-38). | Le choix du transport ne regarde que la présence de `version` (`HermesClient.swift:911`) : OK. La recette de vérification de version de `CLAUDE.md` (grep `pyproject.toml` + `__version__`) ne marche plus, même sur un tag de release : utiliser `/health`, `install-stamp.json` (`baseVersion`) et `git describe --tags`. | petit correctif doc |
| 3 | `/v1/chat/completions` : en-têtes, flux SSE | ✅ `api_server_openai_routes.py` identique : `X-Hermes-Session-Id` lu l. 686 et renvoyé l. 809, `X-Hermes-Session-Key` l. 679, `_register_stream_approval` l. 568. Les résultats du « Probe /v1/chat/completions (H3) » restent donc valables (continuité par ID, `reasoning_content`, `hermes.status`, `hermes.tool.progress`, `approval.request`, `finish_reason: "error"`, `[DONE]`). Seule nouveauté côté agent : une progression « ⚙ processing prompt — N% » pour les modèles locaux llama.cpp, via la ligne d'état existante (`agent/chat_completion_stream_monitor.py:70-72`, `_emit_wait_notice` → `thinking_callback`, `agent/status_output.py:179-183`). Aucun nouveau type d'événement. | Rien à changer. | — |
| 4 | `/v1/responses` (vieux gateways) | ✅ Même fichier, identique. | Rien à changer. | — |
| 5 | 809fec15 et approbations (`POST /v1/runs/{id}/approval`) | ✅ Sur v0.22.2, le code de 809fec15 est **absent** : `api_server_runs.py` est identique au local, aucun `session_authority` dans `gateway/`, pas de `hermes_state_runtime.py`. La route d'approbation est inchangée (`api_server.py:86`), `tools/approval.py` aussi (modes `manual` / `smart` / `off`). De toute façon, 809fec15 ne touche que la création d'un run (`_handle_runs`, `POST /v1/runs`), pas la route `/approval` (patch lu : `api_server_runs.py`, `api_server_run_idempotency.py`). | Cartes d'approbation H3b OK sur v0.22.2. Sur v0.22.1 et `main`, c'est cassé : voir C4. | H3b |
| 6 | Gateway « canonical », private daemon grants | ✅ Absents de v0.22.2 (`gateway/session_authority.py`, `hermes_state_runtime.py`, `hermes_cli/dashboard_auth/native_http.py` n'existent pas au tag). Présents dans v0.22.1 et sur `main`. | Aucun effet sur v0.22.2. Voir C1 à C10 pour v0.22.1 / `main` (futur v0.23.0). | H16 |
| 7 | LaunchAgent, `hermes gateway start/restart/uninstall` | ✅ `hermes_cli/gateway.py` identique, label `ai.hermes.gateway*` (`gateway.py:124-142`). `gateway_service_owner.py` : simple factorisation (`service_definition_homes`, l. 100-108). Correctif de v0.22.2 (#138594, `gateway/host_rendezvous.py`) : un gateway supervisé (launchd compris) ne refuse plus de démarrer après un redémarrage parce qu'un PID recyclé ressemblait à un gateway vivant. Le gateway unique pour tous les profils (#112854) est déjà dans l'install locale. | Rien à changer. Le correctif peut faire disparaître des toasts « Hermes ne répond pas » après un redémarrage du Mac (décrit pour Linux, code générique ; non vérifié sur macOS). | — |
| 8 | Canaux de release (install locale) | ⚠️ `config.yaml` n'a **aucun** enregistrement de canal (`update.installs` absent). Pour une copie git du dépôt officiel sans choix enregistré, le canal par défaut est `stable` (`hermes_cli/update_channel.py:155-158` ; l'origine `git@github.com:NousResearch/hermes-agent.git` correspond à `_GITHUB_ORIGIN`, `source_releases.py:18-20`). Sans choix explicite, la mise à jour ne va qu'en avant (`source_check.py:409`, `source_releases.py:86-95`) : `97a9ae8` ne contient pas `d923a5e`, donc **un `hermes update` aujourd'hui amènerait l'install sur v0.22.2**, pas sur la tête de `main`. Le « on garde `main` » de H0 n'a jamais été enregistré. Suivre `main` demande `hermes update --set-channel main` (code local, identique au tag). | Question ouverte 3 : c'est désormais un choix entre v0.22.2 (même serveur API qu'aujourd'hui, seul l'outil `memory` bouge : #10) et `--set-channel main` (gateway « canonical », lignes C). Lu dans le code, non exécuté. | Q3 |
| 9 | Installeur (onboarding, H14) | ⚠️ Le `scripts/install.sh` du tag `v0.22.2` clone toujours `main` sans option de canal (`install.sh:24` `BRANCH="main"`, options l. 45-64). Mais NotchNotch télécharge le script **de `main`** (`OnboardingViewModel.swift:221`), qui a gagné `--channel stable\|main` (défaut `stable` = dernière release publiée, aussi `HERMES_INSTALL_CHANNEL`) le 15/10 (commit `3857c7b8e`, « new installs land on the latest stable release » ; `install.sh` de `main` l. 26-28, 76-79, 654-690). Si la release est injoignable, une installation neuve échoue au lieu de prendre `main`. `hermes init` n'existe toujours pas (aucun sous-parseur `init` au tag). | Depuis le 15/10, un nouvel utilisateur de NotchNotch reçoit v0.22.2 sans rien changer. L'épinglage d'un tag (`--branch v0.21.6`) devient inutile ; on peut passer `--channel stable` explicitement pour ne pas dépendre du défaut d'un script qui vit sur `main`. Non exécuté. | H14 |
| 10 | Outil `memory` | ⚠️ **Nouveau dans v0.22.2** (absent du local) : l'action `replace` disparaît au profit de `patch` (remplace un passage, garde le reste ; pour réécrire tout un bloc, `old_text` = le bloc entier). Un appel `replace` est refusé avec « Nothing was written » (`tools/memory_tool.py:168`, enum `["add","patch","remove"]` l. 404 et 434). `target` devient obligatoire, plus de défaut `memory` (l. 328). Le séparateur ne change pas (`\n§\n`, `memory_tool_store.py:25`). | `updateMemory` demande de « replace » un bloc sans dire où il est, et `deleteMemory` de le « remove » sans `target` (`ChatViewModel.swift:613-621`, `638-643`). Un bon modèle lit le schéma et s'adapte. Un modèle gratuit faible peut appeler `replace` ou oublier `target`, et l'écriture échoue alors que le toast optimiste dit « Mémoire mise à jour ». Correctif : passer `target` (`memory` pour `.learned`, `user` pour `.user`, `BrainViewModel.swift:343-344`) et demander un `patch` dont `old_text` est le bloc entier. Non testé en direct. | H15 |
| 11 | Fournisseurs mémoire en plugins (H9) | ⚠️ Diagnostic H9 inchangé. Au tag, `plugins/memory/` ne contient que `byterover` et `retaindb` ; le dossier `hindsight/` local est vide et non suivi par git. Les plugins du catalogue vont dans `~/.hermes/plugins/<id>/` (ici `hindsight`, `homeassistant`). `hermes_cli/memory_provider_migration.py` : seulement un délai de nouvelle tentative qui double à chaque échec (jusqu'à 7 jours). | `HermesMemoryConfig.scanInstalledPlugins` ne regarde que `hermes-agent/plugins/memory` (`HermesMemoryConfig.swift:92`) : Hindsight reste invisible. H9 doit scanner les deux dossiers, comme prévu. | H9 |
| 12 | Outils renommés | ✅ `todo_list`, `cronjob_manage`, `process_manage` sont déjà les noms enregistrés dans l'install locale comme au tag (`tools/todo_tool.py:333`, `tools/cronjob_tools.py:1193`, `tools/process_registry.py:2785`) ; les anciens noms restent des alias (`model_tools.py:611`, `_LEGACY_TOOL_ALIASES`). Nouveaux outils différés : `browser_vault`, `set_theme` (`hermes_cli/config_defaults.py:2020-2024`). | `verbMapping` a `cronjob_manage` (`MessageBubble.swift:1046`) mais pas `todo_list` ni `process_manage` : icône et verbe génériques (« Used tool »). Cosmétique. | petit correctif |
| 13 | Missions : `jobs.json`, REST cron | ✅ `cron/` identique au local ; routes `/api/jobs*` identiques (`api_server.py:1753-1758`), whitelist PATCH aussi (`_UPDATE_ALLOWED_FIELDS`, l. 3807). | `CronStore` et pause / reprise / édition OK sur v0.22.2. Sur v0.22.1 / `main`, voir C7. | — |
| 14 | `/api/model/options` (H4) | ✅ Route identique (`api_server.py:2492-2508`). Dans `hermes_cli/inventory.py`, seul le niveau « ultrafast » est maintenant filtré (`ultrafast_offered`, l. 544 et 569) ; forme de la réponse inchangée. | Rien à changer. | H4 |
| 15 | `state.db` | ✅ `SCHEMA_VERSION = 31` (`hermes_state_common.py:283`), comme en H0. `hermes_state_sessions.py` : deux méthodes ajoutées (`model_config`), rien de retiré. `sessions.auto_prune` vaut `true` par défaut (`config_defaults.py:2264-2269`, déjà en local) : les sessions terminées inactives depuis 90 jours sont supprimées au démarrage. Ici `config.yaml` a `sessions.auto_prune: false` (l. 385-386). Problème connu de v0.22.2 (sessions créées sous le gateway 0.22.1 impossibles à supprimer) : sans objet ici. | Les 4 requêtes SQL passent. Sur une install neuve (H14), les conversations de plus de 90 jours disparaissent de l'historique (et leurs titres `TitleStore` restent orphelins). À savoir, pas à corriger. | H14 |
| 16 | Config par défaut, `hermes config set` | ✅ `config_defaults.py` : commentaires, liste d'outils différés, `onboarding.run`. Aucune clé que NotchNotch écrit n'est touchée (`approvals.mode`, `memory.provider`, `model.*`, `display.language`). `approvals.mode: smart` : le verdict se fait sans raisonnement (`tools/approval_smart.py:74-87`). `hermes config set` écrit un chemin inconnu sous une section connue avec un avertissement « did you mean » (`hermes_cli/config.py:3579-3581`). | Le message de configuration du cerveau (`skills.config.wiki.path`) reste accepté. | — |
| 17 | Skills Hub, contrôle du Mac, ancien venv | ✅ `hermes_cli/subcommands/computer_use*` et les modules du Skills Hub sont identiques. Le `venv/` hérité est seulement lu par la migration de `hermes pm` (`pm/extras.py:278-288`) ; je n'ai pas vu de code qui le supprime. ❓ Non vérifié : `hermes pm gc` pendant une mise à jour. | `SkillsHubClient` (venv Python) devrait continuer à marcher ; à revérifier après la mise à jour. | — |

### Gateway « canonical » : v0.22.1 et `main` (futur v0.23.0)

Sans effet sur v0.22.2, mais c'est ce que NotchNotch recevrait avec `hermes update --set-channel main`, et ce qui sortira en v0.23.0. Code lu à `v0.22.1` (`297552a`, noté h221) et `main` (`9e01b44` du 18/10, noté main), sans exécution. Le runtime « canonical » est toujours actif : `initialize_gateway_runtime(runner)` est appelé sans condition (h221 `gateway/run_bootstrap.py:716-717`), donc chaque tour de l'API passe par une « admission » (`gateway/session_api_turn.py`).

| # | Sujet | Constat | Impact NotchNotch | Session |
|---|---|---|---|---|
| C1 | Auth, private daemon grants | ✅ `_check_auth` et le corps du 401 sont identiques au local (h221 et main `api_server.py:1480-1512`). Les « private daemon grants » (en-tête `x-hermes-gateway-ticket`, main `hermes_cli/dashboard_auth/native_http.py:15`) protègent un nouvel écouteur natif, lancé dans le process du gateway sur un port aléatoire (main `gateway/run_api.py:138`). `:8642` reste sur le Bearer, ouvert par une `API_SERVER_KEY` de 16 caractères ou plus. Deux routes ajoutées : `/v1/runs/{id}/clarify`, `/v1/runs/{id}/resolve-unknown`. | Rien à changer. | H16 |
| C2 | Identité de session (`/v1/chat/completions`) | ⚠️ L'admission réécrit `sessions.session_key` avec la route canonique `agent:main:api_server:dm:<id>` (h221 `gateway/session_api.py:172`, main l. 257) : `X-Hermes-Session-Key` n'est plus stocké. **v0.22.1** refuse toute ligne dont `session_key` n'est ni vide ni la route (`session_api.py:163`, `admission_conflict`), et le refus arrive en fin de flux (`finish_reason: "error"`). **main** adopte une fois l'ancienne clé (`session_api.py:233-249`, #139835) et garde un registre clé → ligne dans `state_meta`, puis réécrit `session_key`. | v0.22.1 : chaque reprise d'une conversation existante échoue (l'agent a compté 24 lignes `notchnotch-…` dans `state.db`, lecture seule). main : `SessionStore.latestRowId` (`WHERE session_key = ?`) ne retrouve plus la ligne au 2e tour et envoie la clé comme `X-Hermes-Session-Id`. Une conversation dont l'ID de ligne ≠ la clé (née sur `/v1/responses`) risque de repartir à vide (déduit ; le registre `state_meta` pourrait la rattraper, non vérifié). L'historique (`session_key LIKE 'notchnotch-%'`) retombe sur `s.id`. | H16 |
| C3 | Sessions « natively owned » (809fec15) | ✅ pour NotchNotch. Le refus `permission_denied` vise une ligne dont `source` n'est ni `api_server` ni `bot_room` (h221 `session_api_turn.py:205`, main l. 217). Le message de 809fec15 concerne la création d'un run (`POST /v1/runs`), que NotchNotch n'appelle jamais. | Les lignes NotchNotch sont `api_server`. Seule la reprise depuis l'historique d'une session Telegram ou CLI serait refusée (déduit). | H16 |
| C4 | Approbations (`POST /v1/runs/{id}/approval`) | ⚠️ **Cassé.** La route passe par `_respond_authority_run` (h221 `api_server_runs.py:1298`, main l. 1321), qui exige un corps d'exactement `{request_id, execution_generation, choice}`, sinon `invalid_params` (h221 `api_server_authority_runs.py:100`, main l. 122). `execution_generation` (un entier) arrive dans `approval.request` (`gateway/session_pending_controls.py:28`). Succès : `{run_id, status: "resolved"\|"already_resolved", prompt_id}`, sans compteur `resolved`. Erreurs : 409 `approval_not_pending`, `stale_generation`, `not_found`… ; 400 `invalid_params` ; 503 `runtime_draining`. | NotchNotch envoie `{choice, request_id}` (`HermesClient.swift:792`) → 400 : « Autoriser » ne débloque rien, l'agent attend `approvals.timeout` puis refuse. Correctif : renvoyer `execution_generation` reçu (le gateway local lit seulement `choice` et `request_id`, donc compatible), lire `status`. | H16 |
| C5 | Bouton Stop | ⚠️ Déduit du code : le tour attend `asyncio.shield(waiter)` (h221 `session_api_turn.py:376`, main l. 400) ; fermer le flux ne coupe plus l'agent, le tour va au bout et s'enregistre. Les tours d'une même session passent en file (FIFO). Nouveau `finish_reason: "cancelled"` (`api_server_openai_routes.py:79`). | Stop arrête l'affichage, pas le travail (commande lancée, fichier écrit). À vérifier au curl en H16, et chercher la route d'annulation prévue. | H16 |
| C6 | `/v1/responses` (repli) | ⚠️ Mineur. L'événement final devient `response.<status>` avec `completed`, `failed`, `incomplete` ou `cancelled` (h221 `api_server_openai_routes.py:651`) ; une erreur donne `response.failed`. | Non utilisé sur ces versions (`/health` a `version`). Sinon, `incomplete` / `cancelled` seraient vus comme une fin sans événement final, donc renvoyés. | — |
| C7 | Missions (`jobs.json`) | ✅ Même fichier (h221 et main `cron/jobs.py:90`), mêmes sorties (l. 114, `## Response` / `## Error`). Un champ ajouté, `canonical_completions`. L'exécution passe par le registre d'admissions, mais la sortie reste écrite par le planificateur (main `cron/scheduler_authority.py:1`). | `CronStore` OK (champ inconnu ignoré au décodage). | — |
| C8 | Service gateway | ✅ Même label et même plist (h221 `hermes_cli/gateway.py:2863-2866`), mêmes `start` / `restart` / `uninstall` / `status` ; ajout de `gateway ensure`. Pas de 2e process. Nouveau : le gateway refuse de démarrer si le stockage du profil principal est inutilisable. | `HermesGatewayLauncher` OK. | — |
| C9 | `state.db` | ⚠️ Colonnes lues par NotchNotch inchangées. Ajouts : `sessions.runtime_revision`, `runtime_generation`, tables `runtime_epoch`, `session_admissions`, `worker_*` (h221 `hermes_state_common.py:384`, 511), `SCHEMA_VERSION` 32 sur main. Un trigger empêche un Hermes plus ancien de supprimer une session qui a un historique runtime (h221 l. 692) : c'est le « problème connu » de v0.22.2. | Requêtes SQL OK. Le sens de `session_key` change (C2). | H16 |
| C10 | `/health`, `/api/model/options`, `/api/jobs*` | ✅ Identiques (main `api_server.py:2366-2368`, whitelist PATCH l. 3774). | Rien à changer. | — |

### Cassé si Jérémie passe sur v0.22.2 aujourd'hui

1. **Édition et suppression de mémoire** (#10) : plus d'action `replace`, `target` obligatoire. Les prompts de NotchNotch ne nomment ni l'un ni l'autre ; un modèle faible peut échouer sans que l'interface le voie. → H15.

Le reste tient : chat sur `/v1/chat/completions` (en-têtes, raisonnement, statuts, approbations, erreurs), `/v1/responses`, clé API, `/health`, liste des modèles, missions et REST cron, service launchd, `state.db`. Déjà cassés avant, et pas aggravés : sélecteur de mémoire (H9), `hermes init` dans l'onboarding, icône générique pour `todo_list` / `process_manage`.

### Cassé sur `main` (`--set-channel main`) ou à la sortie de v0.23.0

1. **Approbations** : « Autoriser » / « Refuser » répondent 400 (C4). L'agent attend puis refuse.
2. **Reprise de conversation** : erreur `admission_conflict` à chaque tour sur v0.22.1 ; sur `main`, perte de contexte possible au 2e tour pour les conversations nées sur `/v1/responses` (C2).
3. **Stop** : ne coupe plus l'agent (C5, déduit).

### Questions ouvertes

1. Mise à jour : laisser `hermes update` passer sur v0.22.2 (canal `stable` par défaut, #8), ou `--set-channel main` ? Recommandation : v0.22.2, puis H15 ; garder `main` pour une install de test.
2. Sur `main`, un `X-Hermes-Session-Id` égal à l'ancienne clé est-il résolu par le registre `state_meta` (C2) ? À vérifier au curl en H16.
3. Gateway « canonical » : quelle route annule un tour en cours (C5) ?
4. Après la mise à jour : `/health` dit-il `0.22.2` ? une édition de mémoire passe-t-elle avec le modèle gratuit par défaut ? `SkillsHubClient` (ancien `venv/`) marche-t-il toujours (#17) ?
