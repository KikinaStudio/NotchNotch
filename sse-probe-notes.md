# SSE Probe Notes — `/v1/responses` on Hermes v0.11.0

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
