# Plan: Compute Monitor tab (Android)

A **read-only** tab in Conduit that shows, at a glance, what each compute node behind the
user's **Hermes Agent backend** is doing:

* which nodes are in use;
* what each one is working on;
* how fast it is going;
* how much CPU, GPU, VRAM and RAM it is using.

Tapping a node opens a sheet with more detail. Nothing on this tab does any work: it
starts nothing, stops nothing and changes nothing.

**Android only.** No Cupertino variants and no iOS wiring.

---

## 1. Goals and non-goals

**Goals**

* A top-down network view: the Hermes hub, each node connected to it, active nodes
  highlighted, and animated token flow on every connection that is carrying tokens.
* For every node, at a glance: **what** it is doing, its **speed** in tok/s, and its
  **resource use** (CPU, GPU, VRAM, RAM).
* **Tap a node** to see more detail (§3.3).
* A short line showing what the collective is working on overall.

**Non-goals**

* Any action: no load/unload, stop, steer, approve, or changing models or config. The new
  Hermes API is GET-only, and the app only reads from it.
* Using the tab to chat or to start runs.
* iOS. Ollama, Open WebUI and Direct connections also do not count as nodes.

---

## 2. Definitions

| Term | Meaning |
| --- | --- |
| **Hub** | The Hermes Agent server the app is connected to. It orchestrates work and routes model calls to nodes. |
| **Node** | One machine that serves models for Hermes. It is either a **local machine running llama.cpp** (`llama-server`), including Hermes's own managed local runtime, or a **cloud provider** (OpenRouter, Anthropic, Nous Portal, Gemini, and so on). |
| **Engine** | One `llama-server` endpoint on a local node. One machine can run several engines, and in router mode one engine can host several models. |
| **Work item** | One in-flight model call, labelled with what it is for: a main turn, a subagent and its goal, a scheduled job, a messaging platform, a Desktop session, or "untracked". |

---

## 3. What the user sees

### 3.1 The tab

* There is a new sidebar destination, **Compute**. It is visible only on Android, and only
  while a Hermes connection is enabled (§6.3).
* If the Hermes plugin (§5) is not installed, the tab shows a read-only setup card. The
  card explains the install steps and has a "Copy command" button. Nothing is ever run
  from the phone.

### 3.2 Network view (portrait phone, top-down)

```
 ┌──────────────────────────────────────────────────────────────┐
 │ 3 of 5 nodes busy · 142 tok/s · 2 sessions · updated 0.4 s    │  summary strip
 │ "Refactor the billing module" (dashboard) · Daily digest (cron) │  what the collective is on
 └──────────────────────────────────────────────────────────────┘
                     ┌──────────────────────┐
                     │  HERMES HUB  hermes-1 │  CPU 22% · RAM 41%
                     └──┬──────┬──────┬───┬──┘
          >>>>>>>>>>>>  │      │>>>   │   │ <<<<<<<<<<<<
   ┌────────────────────┴─┐  ┌─┴──────┴─┐ └─┴───────────────────┐
   │● gpu-box-1     51 t/s│  │● OpenRouter│ │○ Anthropic     idle │
   │ Subagent: write tests│  │ Main turn  │ │                     │
   │ GPU ▇▇▇▇▇▇▇▁ 92%     │  │ 33 t/s     │ │                     │
   │ VRAM ▇▇▇▇▇▁▁ 21/24GB │  │ TTFB 0.6 s │ │                     │
   │ CPU ▇▇▁▁▁▁▁ 34%      │  └────────────┘ └─────────────────────┘
   └──────────────────────┘
   ┌──────────────────────┐  ┌──────────────────────┐
   │● gpu-box-2     58 t/s│  │◌ mac-mini    offline │
   │ Daily digest (cron)  │  │ last seen 12 min ago │
   │ GPU ▇▇▇▇▇▁▁ 71% ...  │  └──────────────────────┘
   └──────────────────────┘
```

* **Layout:**
  * On a portrait phone the Hub sits at the top and node cards flow below it in two
    columns: local machines first, then cloud providers.
  * Card order is stable (by kind, then name), so cards never shuffle when activity
    changes.
  * In landscape the same cards sit around the Hub in a ring.
* **A card shows at a glance:**
  * a status dot: active, idle, loading, offline, or error;
  * the node name;
  * a big **tok/s** figure;
  * one line for **what it is doing** (the top work item, plus "+N more");
  * for local nodes, mini bars for **GPU %, VRAM, CPU %** (RAM goes in the detail sheet);
  * for cloud nodes, **TTFB** in place of the resource bars.
* **Highlighting:**
  * Active cards are full contrast and glow in proportion to tok/s.
  * Idle cards are dimmed and compact.
  * Offline cards have a dashed outline and show when they were last seen.
  * Error cards are amber with a reason, for example "probe failed: 401".
* **Connections:** curves from the Hub to each card. When a connection carries tokens,
  particles flow along it:
  * node → Hub for generated tokens;
  * Hub → node as a short burst when a prompt is sent.
  * Particle rate is a capped log scale of tok/s. It is representative, not one particle
    per token.

### 3.3 Tapping a node (read-only detail sheet)

Tapping a card opens a bottom sheet. It can be expanded to full height, and it keeps
updating live while open.

**Every node:**

* **Header:** name, kind (local machine or cloud provider), host or provider ID, status,
  and how recently the data was updated (for example "0.6 s ago").
* **Doing now:** every work item on this node. Each shows:
  * its label, for example "Subagent: write unit tests", "Scheduled job: Daily digest",
    "Dashboard chat: Refactor billing", or "Telegram";
  * the session title, the model, and elapsed time;
  * live tok/s, tokens generated so far, and time to first token.
* **Speed:** generation and prompt tok/s now, plus a 60-second sparkline of each.
* **Totals for the last hour:** requests, tokens in and out, and errors.

**Local machines also show:**

* **System resources:**
  * CPU % and load average;
  * RAM used and total;
  * for each GPU: name, utilisation %, VRAM used and total, temperature, and power draw
    (where the platform reports them).
* **Engines:** one row per `llama-server`, showing:
  * the model or models, with file size and context size;
  * state: ready, loading (with %), sleeping, or offline;
  * busy and total slots, and queue depth;
  * the llama.cpp build, and whether `--metrics` is enabled.
* **Missing-data hints** in plain language, for example "Prompt speed needs llama-server
  `--metrics`", or "Install the node-stats helper on this machine for CPU/GPU figures".

**Cloud providers also show:**

* models in use;
* median time to first token;
* recent errors (status code and time only);
* the upstream provider when OpenRouter reports one.

**Tapping the Hub** shows the Hermes version, host resources, running sessions, and the
node inventory with each node's role: main model, subagents, auxiliary tasks, or MoA.

The sheet has **no action buttons**. The only interactions are close and expand.

### 3.4 Accessibility and motion

* **Reduce motion** (`context.reduceMotion` in `lib/shared/theme/theme_extensions.dart`,
  plus the app animation settings) turns off particles and glow pulses. The numbers and
  bars stay.
* Every card has `Semantics`, for example "gpu-box-1, active, 51 tokens per second,
  running subagent write unit tests, GPU 92 percent".
* A **List** toggle replaces the canvas with a plain list of cards.
* Colours come from `conduit_theme` tokens and work in both light and dark.

---

## 4. Architecture overview

All data comes from the **Hermes Agent backend**. The phone never talks to llama.cpp
machines or providers directly. There are two reasons:

* Hermes's managed `llama-server` binds to `127.0.0.1` with a generated `--api-key`
  (`hermes_cli/local_runtime/supervisor.py:150-160`), so the phone cannot reach it.
* Only Hermes knows which call is for which task.

```
 Hermes host
 ┌──────────────────────────────────────────────────────────────────────────┐
 │  Agent processes: the dashboard server (chats from the browser and from  │
 │  Conduit) and, if it runs, `hermes gateway` (cron, messaging, API server)│
 │    └─ conduit-compute hooks ── content-free activity records ──┐         │
 │                                     ~/.hermes/conduit-compute/activity/  │
 │  Dashboard server (`hermes dashboard`, the one you open in a    │        │
 │  browser; port 9119 by default)                                 │        │
 │    └─ conduit-compute API  ◀────────────────────────────────────┘        │
 │         ├─ inventory from Hermes config (main, providers, managed        │
 │         │   runtime, auxiliary, MoA, delegation)                         │
 │         ├─ polls llama.cpp engines: /health /props /slots /metrics       │
 │         ├─ Hub resources: psutil + nvidia-smi                            │
 │         └─ remote machine resources: node-stats helper (optional)        │
 └──────────────┬───────────────────────────────────────────────────────────┘
                │  GET /api/plugins/conduit-compute/snapshot   (1 Hz, while the tab is visible)
                ▼
 Android: Compute tab (renders the snapshot; no other network calls)
```

Two pieces get built:

1. A **Hermes plugin, `conduit-compute`** (Python), kept in this repo. It observes,
   samples and serves one snapshot (§5).
2. The **Compute tab** in the Android app. It polls the snapshot and renders it (§6).

### 4.1 Connecting to the Hermes dashboard (Desktop Gateway), behind an IP allowlist

**"Desktop Gateway" is Conduit's name for connecting to the Hermes dashboard server.**
That is the same server (`hermes dashboard`, port 9119 by default) that you open in a
browser. It serves the web UI, the REST API (`/api/*`) and the chat WebSocket (`/api/ws`,
`hermes_cli/web_routers/chat_ws.py:561`). The name comes from Hermes's desktop-app
contract (`DESKTOP_BACKEND_CONTRACT` in `tui_gateway/server.py`), which the dashboard
implements.

**Setup in Conduit:**

1. Settings → Hermes → add a connection.
2. Mode: **Desktop Gateway**.
3. URL: the **same dashboard URL you use in the browser**.
4. Authentication: **Dashboard**. This opens the dashboard's own sign-in page in a
   WebView, the same login as the browser.

Separately, Conduit warns "Desktop Gateway is stopped" when the dashboard reports
`gateway_running: false`. That flag is about Hermes's **other** process, `hermes gateway`
(messaging platforms, cron, API server). The dashboard and the tab work without it. Cron
and messaging work simply won't appear unless that process runs.

**Access:** Hermes has no client-IP allowlist of its own (it has only
`dashboard.trusted_proxies`, for forwarded headers), so the allowlist is enforced in front
of it by a firewall, reverse proxy or VPN ACL.

| Path | Who connects | Allowlist change |
| --- | --- | --- |
| Phone → Hub dashboard | The app, to `/api/plugins/conduit-compute/*` on the **same origin and port** as the browser dashboard, with the same login and access headers | **Same rule as your browsers.** If the phone can already open the dashboard, nothing changes. If not, the phone needs the access your browsers have: its IP added to the allowlist, or the phone joined to a network or VPN that is already allowed. Plugin routes are not in `PUBLIC_API_PATHS` (`hermes_cli/dashboard_auth/public_paths.py`), so they sit behind the dashboard sign-in like everything else. |
| Hub → llama.cpp machines | The plugin, from the Hub's IP | Each `llama-server` port only needs to accept the **Hub's IP**. The phone never needs access to a node. |
| Hub → `node_stats.py` helpers | The plugin, from the Hub's IP | The helper has its own `allow_ips` (default: only the Hub's IP) plus a shared token, and binds to one chosen interface. |
| Hub → cloud providers | Unchanged | None |

* **No new ports are opened on the Hub.**
* **When the phone is on a network outside the allowlist** (for example mobile data with
  no VPN), the tab behaves like the rest of the Hermes features in the app. It keeps the
  last snapshot with its age and shows why it can't refresh:
  * timeout or refused connection → "Hermes is not reachable from this network";
  * 401 → "Sign in to Hermes again";
  * 403 → "This device is not allowed";
  * 404 on the plugin → setup card;
  * unknown schema → "Update the plugin".

---

## 5. Hermes side: the `conduit-compute` plugin

It lives in this repo at `hermes-plugin/conduit-compute/` and is installed into
`~/.hermes/plugins/conduit-compute/`, then enabled through `plugins.enabled`. User
plugins must be listed there before their Python runs; that gate is
`_plugin_api_mount_skip_reason` in `hermes_cli/web_server_dashboard.py`.

```
hermes-plugin/conduit-compute/
  plugin.yaml              name, version, hooks: [pre_api_request, post_api_request,
                           api_request_error, on_stream_start, on_stream_delta,
                           on_stream_end, subagent_start, subagent_stop]
  __init__.py              register(ctx): hook handlers → activity records
  activity_store.py        per-process ring of in-flight + recent calls; atomic JSON file
  dashboard/
    manifest.json          {"name": "conduit-compute", "api": "plugin_api.py",
                            "tab": {"hidden": true}}   ← API only, no dashboard tab
    plugin_api.py          FastAPI router mounted at /api/plugins/conduit-compute/
  inventory.py             Hermes config → nodes and engines
  llama_probe.py           server-side llama.cpp polling + Prometheus text parsing
  host_stats.py            psutil + nvidia-smi for the Hub (same facts as
                           /api/local-models/hardware and /api/system/stats)
  node_stats/node_stats.py optional zero-dependency helper for remote llama.cpp machines
  config.example.yaml      per-node display names, node-stats URLs/tokens, poll interval;
                           node_stats.py bind address + allow_ips (default: Hub IP only)
  tests/                   pytest
```

### 5.1 Attribution: "what is each node doing?" (agent hooks)

These are the same public observability hooks the bundled Langfuse plugin uses
(`plugins/observability/langfuse/`). They fire in **every** process that runs an agent,
so the work they capture covers **every** session on the Hub. That includes cron jobs,
messaging platforms, other clients and subagents, not only the phone's own chats.

| Hook | Fields used (verified) | Source |
| --- | --- | --- |
| `pre_api_request` | `api_request_id`, `session_id`, `task_id`, `turn_id`, `platform`, `model`, `provider`, `base_url`, `api_call_count` | `agent/turn_api_request.py:64` |
| `post_api_request` | `api_request_id`, `started_at`, `first_chunk_at` (gives TTFB), `api_duration`, `usage` (token buckets), `response_model` | `agent/turn_response_intake.py:63` |
| `api_request_error` | status code and error class only | `agent/api_request_hooks.py` |
| `on_stream_start/delta/end` | `session_id`, `model`, `provider`, `surface`, plus **only the length** of `delta` (both text and reasoning kinds) | `agent/stream_delivery.py:269-334` |
| `subagent_start/stop` | `parent_session_id`, `child_session_id`, `child_goal`, `child_role` | `tools/delegate_tool.py:287` |

**How events become records:**

* **Node key:**
  * If `base_url` is local, the key is the normalised host. "Local" uses Hermes's own
    `agent.model_metadata.is_local_endpoint`.
  * Otherwise the key is the canonical provider ID. `custom` is resolved to `custom:<name>`
    the same way `tui_gateway/server.py` does it.
* **Label:**
  * A `child_session_id` that has been seen in `subagent_start` gets "Subagent: <goal>".
  * Otherwise the label comes from the platform:
    * `tui` is a dashboard chat, from the browser or from Conduit, and gets
      "Dashboard chat: <title>". The dashboard tags its sessions `platform="tui"` in
      `tui_gateway`.
    * cron gives "Scheduled job: <name>".
    * telegram, discord and the other messaging platforms give the platform name.
    * `api_server` gives "API: <title>".
  * Session titles are looked up in the Hermes session DB (`hermes_state`), read-only and
    cached.
* **Live tok/s:** an EWMA of streamed characters ÷ ~4 per token, replaced by exact
  `usage` counts when `post_api_request` arrives.

**The store:**

* Each process keeps a small ring of in-flight and recent calls.
* It writes `~/.hermes/conduit-compute/activity/<pid>.json` by atomic replace, at most
  2 times a second, and only while there is recent activity.
* The API side merges files whose PID is still alive and whose modification time is under
  10 s old.

**Content is never kept.** The hooks also receive `user_message`, `conversation_history`,
`request_messages`, `response`, `assistant_message` and the delta text. The plugin ignores
all of them and records only IDs, model and provider names, timings and counts.

### 5.2 Inventory: which nodes exist

The plugin reads Hermes config server-side with Hermes's own loaders. Secrets stay on the
Hub. Sources:

* the main `model` block;
* `providers:` custom endpoints (the same data as `GET /api/providers/custom-endpoints`);
* the **managed local runtime** (`hermes_cli.local_runtime.endpoint._state_endpoint()`
  gives `base_url` and `api_key`; loaded models and load progress come from the same
  helpers that back `GET /api/local-models/status`);
* `auxiliary.*`, `moa`, and `delegation` slots that set a `base_url` or provider.

Local endpoints are grouped by host into machines. Every provider ID that is not local is
one cloud node.

### 5.3 Speed and engine state (server-side llama.cpp polling)

* The plugin polls each **local** engine **only while a snapshot was requested in the last
  15 s**, so it costs nothing when nobody is looking. Cloud URLs are never probed.
* Poll interval is 1 s per engine, with jitter. Each engine's own key is used.

| Endpoint | Used for |
| --- | --- |
| `GET /health` | Reachability. 503 means "loading". |
| `GET /props` | `total_slots`, `model_path`, `is_sleeping`, `build_info`. This is also how an engine is identified as llama.cpp; vLLM and LM Studio show as "local, no engine telemetry". |
| `GET /v1/models` (or `GET /models` in router mode) | Models, `meta.size`, `meta.n_ctx_train`, and which models are loaded |
| `GET /slots` (`?model=` in router mode) | Per slot: `is_processing`, `id_task`, `n_ctx`, `next_token.n_decoded` |
| `GET /metrics` (`?model=` in router mode; needs `--metrics`) | `llamacpp:predicted_tokens_seconds`, `prompt_tokens_seconds`, `tokens_predicted_total`, `prompt_tokens_total`, `requests_processing`, `requests_deferred` |

* **Generation tok/s:** Δ`tokens_predicted_total` / Δt when metrics are on. Otherwise,
  Σ Δ`n_decoded` over processing slots / Δt; a change in `id_task` counts as a new
  request, not a negative rate.
* **Prompt tok/s** needs metrics.
* Hermes's managed runtime always runs with `--metrics --slots` in router mode
  (`supervisor.py:150-160`).
* **Untracked work:** if slots are busy but no attributed call explains it, the node shows
  "Untracked". This catches auxiliary calls, which do not fire the request hooks (§9), and
  other clients of the same `llama-server`.

### 5.4 Resource usage

* **The Hub host:**
  * psutil gives CPU %, load average, and RAM.
  * nvidia-smi gives GPU name, utilisation, VRAM used and total, temperature, and power.
    This extends the query in `hermes_cli/web_routers/local_models.py:_nvidia_smi_facts`.
  * VRAM total and UMA come from `local_runtime.hardware`.
  * Other GPU vendors show fewer readouts, and the UI hides what is missing.
* **Remote llama.cpp machines:** llama.cpp reports no system resources, so an optional
  helper `node_stats.py` runs on each machine.
  * It is stdlib only, using psutil and nvidia-smi or rocm-smi when they are installed.
  * It serves `GET /stats` with the same field names as the Hub.
  * It binds to one configured interface (LAN or VPN).
  * It accepts requests only from `allow_ips`, which defaults to the Hub's IP, and only
    with a shared token set in the plugin config. This matches the IP-allowlist policy in
    §4.1.
  * The plugin scrapes it at 1 s alongside the engine polls.
* **Without the helper,** the node's card shows speed and work only, and its detail sheet
  explains how to add the helper.

### 5.5 Snapshot API (GET-only)

* `GET /api/plugins/conduit-compute/health` returns `{"schema": 1, "version": "…"}`. The
  app uses it to detect the plugin.
* `GET /api/plugins/conduit-compute/snapshot` returns:

```json
{
  "schema": 1,
  "generated_at": 1761040000.4,
  "hub": {"name": "hermes-1", "version": "…", "resources": {"cpu_percent": 22, "ram_used": 0, "ram_total": 0, "gpus": []},
          "sessions": [{"title": "Refactor the billing module", "surface": "dashboard", "running_for_s": 134}]},
  "nodes": [
    {"id": "local:192.168.1.20", "kind": "local", "label": "gpu-box-1", "status": "active", "last_seen": 1761040000.1,
     "speed": {"gen_tps": 51.2, "prompt_tps": 812.0, "gen_tps_60s": [0, 12.1, 48.0], "prompt_tps_60s": []},
     "resources": {"cpu_percent": 34, "load_avg": [2.1, 1.8, 1.5], "ram_used": 0, "ram_total": 0,
                   "gpus": [{"name": "RTX 4090", "util_percent": 92, "vram_used": 0, "vram_total": 0, "temp_c": 71, "power_w": 310}]},
     "engines": [{"id": "e1", "models": [{"id": "qwen3-coder-30b", "size_bytes": 0, "n_ctx": 32768, "state": "ready"}],
                  "slots_busy": 2, "slots_total": 4, "queue": 0, "metrics": true, "build": "b6xxx"}],
     "work": [{"kind": "subagent", "label": "Subagent: write unit tests", "session_title": "Refactor the billing module",
               "surface": "dashboard", "model": "qwen3-coder-30b", "elapsed_s": 41, "gen_tps": 38.0,
               "tokens_out": 1203, "ttfb_ms": 420}],
     "last_hour": {"requests": 57, "tokens_in": 0, "tokens_out": 0, "errors": 0},
     "hints": []},
    {"id": "cloud:openrouter", "kind": "cloud", "label": "OpenRouter", "status": "active",
     "speed": {"gen_tps": 33.0}, "resources": null, "ttfb_ms_p50": 610, "upstream": "Fireworks",
     "work": [], "last_hour": {}, "recent_errors": [{"status": 429, "at": 1761039900}]}
  ]
}
```

* The plugin keeps the 60 s history, so the detail sheet is complete the moment it opens.
* The schema is versioned. The app rejects unknown major versions and shows an "update the
  plugin" card.

---

## 6. Android app side

### 6.1 Core, Flutter-free: `packages/conduit_core/lib/features/compute_monitor/`

This follows the repo rule that logic lives in `conduit_core`, enforced by
`tool/check_package_boundaries.dart`.

```
models/compute_snapshot.dart     Immutable, defensive fromJson for schema 1
                                 (Hub, ComputeNode, Engine, Gpu, WorkItem, Speed, Hints)
services/compute_monitor_client.dart
                                 GET health/snapshot through the existing Hermes Desktop
                                 REST session (auth, access headers and TLS settings
                                 already handled by HermesDesktopApiService._requestJson)
providers/compute_monitor_providers.dart
                                 autoDispose stream provider: polls at 1 Hz only while
                                 watched and the app is resumed; backs off from 1 s to
                                 15 s on failure; keeps the last good snapshot with an age
                                 and a typed failure (unreachable / unauthorised /
                                 forbidden / plugin missing / schema too new; see §4.1)
```

Small Hermes service change: expose a typed `getPluginJson(name, path)` on
`HermesDesktopApiService` that is restricted to `/api/plugins/conduit-compute/`. It is
read-only, and nothing else in the Hermes services changes.

### 6.2 App: `lib/features/compute_monitor/`

```
views/compute_monitor_tab.dart   tab body: summary strip, canvas or list, setup card
widgets/compute_layout.dart      pure: (nodes, size, orientation) → card rects + edge curves
widgets/compute_canvas.dart      one CustomPainter for edges + particles under the cards;
                                 one Ticker; RepaintBoundary
widgets/node_card.dart           glanceable card (§3.2), Semantics
widgets/node_detail_sheet.dart   read-only detail sheet (§3.3), live-updating
widgets/hub_detail_sheet.dart
widgets/mini_bar.dart, sparkline.dart
widgets/compute_setup_card.dart  install steps + "Copy command"
```

UI controls go through the `platform_ui` facade, as `tool/platform_ui_lint.dart` requires
in CI.

### 6.3 Registration (Android only)

* Add `SidebarTabId.compute` to
  `packages/conduit_core/lib/features/navigation/models/sidebar_navigation_model.dart`.
* Register a descriptor in `lib/features/navigation/widgets/sidebar_tab_registry.dart`
  with a Material icon such as `Icons.hub_outlined` / `Icons.hub`. The required SF Symbol
  fields get placeholder names, because they never render on Android.
* Visible when `defaultTargetPlatform == TargetPlatform.android` **and** Hermes is enabled
  **and** the active Hermes connection is in Desktop Gateway mode
  (`HermesBackendMode.desktopGateway`, the mode in use). Responses API connections are out
  of scope.
* Add localised strings to `lib/l10n/app_en.arb`, each with an `@key` description, and
  mirror them in all 14 locales (checked by `tool/validate_arb_locales.dart` and
  `tool/verify_arb_descriptions.dart`).

### 6.4 Rendering and battery

* The canvas runs on a **single Ticker**. It is muted when the tab is not the active
  layer, stopped on pause, and stopped whenever every rate is zero. In that last case it
  paints once and idles, in the same spirit as `ConduitStreamingOrbit`.
* Snapshots arrive at 1 Hz. The painter interpolates tok/s and glow between snapshots, so
  data updates never rebuild layout.
* Cards rebuild only when their own values change, using `select`.
* Particles are capped at 300, from a pool with no per-frame allocation.
* **Budget:** under 4 ms of UI-thread work per frame on a Pixel 6a-class phone with 8
  nodes. Check with `flutter run --profile` and `lib/platform/frame_profiler.dart`.
* **Network:** one small GET per second, and only while the tab is on screen.

---

## 7. Phases

### Phase 0: Verify contracts (≈1 day)

Test against a real Hermes at the commit Conduit targets.

* Confirm that request and stream hooks fire for dashboard chats (started from the browser
  and from Conduit), cron jobs and messaging (only when `hermes gateway` runs), and
  subagents. Check this also with `dashboard.turn_isolation` on, where agents run in the
  compute-host child process (`tui_gateway/compute_host.py`).
* Check whether MoA reference calls fire `pre_api_request` (`agent/moa_loop.py` has its
  own stream path).
* Confirm that a `tab.hidden` API-only dashboard plugin mounts, and that Conduit's
  Dashboard sign-in (the same login as the browser) reaches `/api/plugins/*` through your
  IP allowlist.
* Record `/slots`, `/metrics` and `/props` fixtures from the managed router runtime and from
  a plain `llama-server`.
* **Exit:** fixtures, plus notes appended here.

### Phase 1: Hermes plugin (≈3–4 days)

* Hooks and activity store, inventory, llama.cpp poller, Hub stats, the `node_stats.py`
  helper, the snapshot API, and an install README.
* pytest coverage: hook → record mapping, the content-free guarantee, multi-process
  merge, router-mode polling, rate derivation, and the snapshot schema.
* A small CI job in `.github/workflows/ci.yml` runs the plugin tests.

### Phase 2: App data layer (≈1–2 days)

* Snapshot models and parsing (fixtures from Phase 1), the client, providers, and polling
  lifecycle.
* Unit tests in `packages/conduit_core/test/features/compute_monitor/` use
  `package:checks`, `mocktail`, and `fake_async`.

### Phase 3: Tab and node detail (≈3 days)

* Tab registration and gating, layout, node and Hub cards, summary strip, the **node
  detail sheet** and **Hub sheet**, the list view, setup, empty, offline and old-plugin
  states, and l10n.
* Widget tests in `test/features/compute_monitor/` cover layout stability, highlight
  states, that detail sheets open on tap and update live, semantics, and that the tab is
  hidden off Android.

### Phase 4: Live animation (≈2 days)

* Particles, interpolation, glow, the reduce-motion path, the idle stop, and a
  profile-mode performance pass on device.

### Later (only if wanted)

* An SSE `/stream` endpoint in place of polling.
* An upstream Hermes PR so auxiliary calls fire the request hooks.

---

## 8. Testing

* **Plugin:** pytest with recorded hook payloads and llama.cpp fixtures.
* **App:** unit and widget tests as above. Run `flutter analyze`,
  `dart run tool/run_test_shards.dart`, `dart tool/platform_ui_lint.dart`,
  `dart run tool/check_package_boundaries.dart`, and the ARB validators.
* **Manual matrix:**
  * Android ARM emulator plus one physical phone.
  * A Hub with the managed local runtime, a second llama.cpp machine with
    `node_stats.py`, and one with no helper and no `--metrics`.
  * One cloud provider.
  * A delegated task with two subagents, a cron job running alongside it, Hub restart,
    and Wi-Fi loss.
  * The phone on an allowed IP, and on a network outside the allowlist (expect the
    "not reachable" state, with the last snapshot kept).
  * llama.cpp machines and `node_stats.py` firewalled to the Hub's IP only (the phone
    can't reach them, and the tab still shows full data).
  * Light/dark, TalkBack, and reduce motion.

---

## 9. Security, privacy, and limits

* **Read-only end to end.** The plugin exposes only GET routes and makes only GET requests
  to engines and helpers. The app makes only GET requests to the plugin.
* **No content leaves the hooks.** Prompts, history, responses and delta text are ignored
  and never stored (§5.1), and tests enforce this. Engine `/slots` bodies may contain
  sampling params or prompt text, so only numeric and state fields are read.
* **Secrets stay on the Hub.** Engine API keys and provider keys are read through Hermes's
  own config resolution and are never returned in the snapshot. Base URLs of local
  engines are reduced to host labels.
* **Plugin trust:** it is a user plugin, so it runs only after being added to
  `plugins.enabled`, which is Hermes's own gate.
* **Access:** the snapshot is behind dashboard auth and the existing IP allowlist, and it
  adds no public paths. Nodes and helpers accept only the Hub (§4.1).
* **Known limits:**
  * Auxiliary calls (vision, compression, titles) do not fire the request hooks. On local
    nodes they show as "Untracked"; on cloud providers they are not visible.
  * Cloud nodes have no resource figures.
  * Live tok/s for cloud calls is estimated from stream length until the exact usage
    arrives at the end of each call.

---

## 10. Decisions and open questions

**Decided**

* **Connection:** you use the Hermes dashboard in a browser. In Conduit that is the
  **Desktop Gateway** mode, pointed at the same dashboard URL and signed in with
  **Dashboard** auth. Access is restricted to specific IPs, so the phone needs the same
  access as your browsers (§4.1).

**Open**

1. **Remote machines:** are your remote llama.cpp machines NVIDIA? That decides whether
   `node_stats.py` needs `rocm-smi` or Apple Silicon support in Phase 1.
2. **Hub numbers:** should the Hub card show its own CPU/RAM figures, or only connect the
   nodes?
3. **Where the allowlist lives:** is it a firewall, reverse proxy, or VPN ACL? If a
   reverse proxy sits in front of the dashboard, its address belongs in
   `dashboard.trusted_proxies` so Hermes records real client IPs. The tab works either
   way.
