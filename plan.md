# Plan: Live Compute Dashboard (Android)

A live, top-down "network" view of the collective: which compute nodes are working right
now, tokens flowing between them in real time, and the task the collective is working on.
**Android only.** Nothing in this plan targets iOS. That means no Cupertino variants, no SF
Symbols, and no iOS native tab bar wiring.

---

## 1. Definitions

| Term | Meaning in this plan |
| --- | --- |
| **Node** | One machine that serves models. Two kinds: (a) a **local machine running one or more llama.cpp `llama-server` endpoints** that Hermes Agent calls, or (b) a **cloud provider** that Hermes calls (OpenRouter, Anthropic, Nous Portal, Gemini, and so on). |
| **Engine** | One `llama-server` process (one base URL / port) on a local node. A machine with three ports is **one node with three engines**. |
| **Hub** | The Hermes Agent server Conduit is connected to. It orchestrates the work and routes calls to nodes. It is not itself a compute node. |
| **Collective** | The Hub plus every node it can route to: main model, delegated subagents, Mixture-of-Agents (MoA) reference and aggregator models, and auxiliary models. |
| **Task** | What the collective is doing now: the running Hermes session's title, latest prompt, todo list, active subagents, and MoA phase. |
| **Client** | This Android device ("You"). |

Ollama, Open WebUI and Direct connections are **out of scope** as nodes. A node is a
llama.cpp machine or a cloud provider used by Hermes.

---

## 2. What the user sees

### 2.1 Network view (default)

```
                 ┌──────────────── summary strip ────────────────┐
                 │ 3/5 nodes active · 142 tok/s · 18.2k tokens    │
                 └────────────────────────────────────────────────┘

   [gpu-box-1]  ●══════>>>>══════╗                ╔═══════○ [Anthropic]
   2/4 slots ◕                   ║                ║        idle
                                 ▼                ║
   [gpu-box-2]  ●═══>>>>>>>>═══▶ ( HERMES HUB ) ◀═╝ <<<══● [OpenRouter]
   1/1 slots ●                   ◉ 2 subagents        ▲    routing → Fireworks
                                 │                    │
   [mac-mini]   ○ - - - - - - - -│                    │
   offline                       ▼ >>>>               │
                              ( YOU )                 │

  ┌──────────────────────── task panel (draggable sheet) ─────────────────────┐
  │ ▶ "Refactor the billing module"        running · 02:14 · 18.2k tokens     │
  │   ☑ read billing/*.py   ☐ write tests   ☐ open PR                         │
  │   subagent #1  "write unit tests"   on gpu-box-1 · qwen3-coder · 51 tok/s  │
  │   subagent #2  "review diff"        on OpenRouter · deepseek  · 33 tok/s   │
  │   MoA: 2/3 references done → aggregating on Anthropic                     │
  └────────────────────────────────────────────────────────────────────────────┘
```

* **Layout (top-down):** Hub in the centre and Client below it. Local nodes sit on the
  left arc and cloud providers on the right arc. Positions are stable, based on a sort
  plus a hash of the node ID, so nodes never jump when the set changes. Up to 12 nodes are
  drawn; any extra collapse into a "+N" node that opens a list.
* **Active nodes are highlighted:**
  * Glow and pulse strength scale with activity.
  * A ring gauge on each local node shows busy slots out of total slots.
  * Cloud nodes show a cloud glyph and pulse while they have attributed in-flight work.
  * Idle nodes are dimmed.
  * Offline or unreachable nodes have a dashed grey outline.
  * Probe errors show in amber with a badge.
* **Edges** are curves between Hub and node, and between Hub and Client. An idle edge is a
  faint hairline. An active edge takes the node's accent colour.
* **Token animation:** particles travel along the edge.
  * Node → Hub is generated tokens. Hub → node is prompt tokens, sent as a short burst
    when a request starts.
  * Reasoning tokens use a lighter shade.
  * Hub → Client is the stream to the user.
  * Particle spawn rate is a capped log scale of tokens/sec, so 5 tok/s and 500 tok/s both
    read correctly. It is representative, not one particle per token.
* **MoA:** while references run, their nodes' edges light up together. When `moa.phase =
  aggregator` fires, the reference edges fade and the aggregator node's edge lights.
* **Subagents** appear as small satellites around the Hub, each linked by a thin leader
  line to the node it is running on.
* **Untracked work:** if a local node is busy but no attributed Hermes work explains it,
  the node still lights up and shows "untracked work". Examples are a cron job, an
  auxiliary task, or another client.

### 2.2 Node detail (tap a node → bottom sheet)

* **Name, kind, host, and engines.** Each engine shows its model, `n_ctx`, and a state:
  loading, ready, sleeping, or offline.
* **Live stats:**
  * Generation and prompt tok/s.
  * Busy and total slots.
  * Queue depth (`requests_deferred`).
  * Requests processing.
  * Tokens generated since the dashboard opened.
* A 60-second tok/s sparkline.
* **What is running on this node now:** the main agent turn, subagent goals, MoA slot
  labels, or "untracked".
* **Cloud nodes:** model(s) in use, the OpenRouter upstream (when it is reported), and
  token counts attributed this session.

### 2.3 Task panel

A draggable sheet built from the focused running Hermes session:

* The title (`session.info.title`) and the latest user prompt, truncated.
* Status: thinking, running a tool, streaming, or waiting for approval. Elapsed time comes
  from `turn_started_at`.
* The todo list (`todo.updated`).
* Active subagents with their goal, node, model, and tok/s.
* MoA progress (`refs_done/refs_total`).
* If several sessions are running (`session.active_list`), a chip row switches between
  them.

### 2.4 Accessibility and motion

* **Reduce motion** (`context.reduceMotion`, `lib/shared/theme/theme_extensions.dart`, plus
  the app animation settings in `lib/shared/services/animation_service.dart`) turns off
  particles. Edges then show static thickness and numeric tok/s labels instead.
* Every node and edge has `Semantics`, for example "gpu-box-1, active, 2 of 4 slots,
  51 tokens per second".
* A **List** toggle gives a TalkBack-friendly table of nodes in place of the canvas.
* Colours come from `conduit_theme` tokens and work in both light and dark.

---

## 3. Data sources (verified against `hermes-src` and llama.cpp)

The dashboard fuses three layers:

* **Inventory:** which nodes exist.
* **Telemetry:** ground truth on whether a node is computing right now.
* **Attribution:** which part of the task each node is doing.

### 3.1 Inventory: which nodes exist

From the Hermes dashboard REST API (Desktop Gateway mode). These calls are profile-scoped,
like the existing `/api/sessions` and `/api/cron`.

| Endpoint | Gives | Source |
| --- | --- | --- |
| `GET /api/model/info` | Main `model`, `provider`, effective context length | `hermes_cli/web_routers/models.py:52` |
| `GET /api/providers/custom-endpoints` | Every named custom endpoint: `id`, `name`, `base_url`, models, and which one is active. **This is the llama.cpp machine list.** | `hermes_cli/web_routers/config_env.py:529` |
| `GET /api/model/auxiliary` | Per-task `{task, provider, model, base_url, local_endpoint}` for vision, web_extract, compression, title generation, and so on | `models.py:172` |
| `GET /api/model/moa` | MoA `reference_models[]` and `aggregator` slots (provider/model) | `models.py:199` |
| `GET /api/system/stats` | CPU, memory and load for the **Hub host**, shown on the Hub node | `web_routers/status.py:469` |
| Delegation config (`delegation.provider/model/base_url`) | Where subagents run | `tools/delegate_tool_config.py`. It is only reachable through `GET /api/config/raw` (raw YAML). See §8 on why that endpoint is risky. |

**Grouping into nodes:**

* Custom endpoints are grouped by normalised host, so several ports on one machine become
  one node with many engines.
* Every other provider ID (`openrouter`, `anthropic`, `nous`, `gemini`, and so on) is one
  cloud node.
* `local_endpoint`, using Hermes's `is_local_endpoint` (RFC-1918, Tailscale CGNAT,
  `.local`, unqualified hosts), decides local versus cloud for custom URLs.

**Manual node overrides (stored in Conduit).** A base URL as Hermes sees it, such as
`http://localhost:8080/v1` when llama.cpp runs on the Hub's own host, is often not
reachable from the phone. Each discovered engine can therefore take:

* a **probe URL override** (for example `http://192.168.1.20:8080` or a Tailscale name);
* an optional **llama.cpp `--api-key`**, held in secure storage;
* a display name and an accent colour;
* "Allow self-signed certificate", reusing the existing Direct/Hermes TLS pattern
  (`server_tls_http_client_factory.dart`).

Users can also add a node by hand that Hermes config does not list.

### 3.2 Telemetry: is the node computing right now? (llama.cpp nodes)

Each engine is polled directly from the phone. Android already permits cleartext to LAN
hosts (`android/app/src/main/res/xml/network_security_config.xml` has
`cleartextTrafficPermitted="true"`).

| Endpoint | Availability | Used for |
| --- | --- | --- |
| `GET /health` | Always on, no API key | Reachability. 503 means "loading model". |
| `GET /props` | On by default | `total_slots`, `model_path`, `is_sleeping`, `build_info` (fetched once, refreshed every 60 s) |
| `GET /v1/models` | On by default | Model `id` (or alias), `meta.n_params` and `meta.size` (fetched once) |
| `GET /slots` | On by default (`--no-slots` turns it off) | Per slot: `id`, `id_task`, `is_processing`, `n_ctx`, `next_token.n_decoded`, `next_token.n_remain`. **The primary live signal.** |
| `GET /metrics` | Only with `--metrics` | Prometheus: `llamacpp:predicted_tokens_seconds`, `llamacpp:prompt_tokens_seconds`, `llamacpp:tokens_predicted_total`, `llamacpp:prompt_tokens_total`, `llamacpp:requests_processing`, `llamacpp:requests_deferred`, `llamacpp:n_busy_slots_per_decode` |
| Router mode (`--models-dir`) | When used | `GET /models` lists loaded models. `/metrics` then needs `?model=<id>`. |

**How rates are derived:**

* Generation tok/s comes from Δ`tokens_predicted_total` / Δt when `/metrics` exists.
* Otherwise it comes from Σ Δ`n_decoded` across processing slots / Δt. A slot whose
  `id_task` changed counts as a new request; its decode counter reset is not read as a
  negative rate.
* Prompt tok/s comes from Δ`prompt_tokens_total`. Without metrics, a burst is inferred
  when a slot moves from idle to processing.
* Rates are smoothed with an EWMA (τ ≈ 1.5 s) and decay to zero after 3 s with no samples.

**Polling and battery:**

* Polling runs only while the dashboard route is visible and the app is resumed.
* It runs at 1 Hz per engine, with jitter, and at most 4 requests in flight at once.
* After repeated failures it backs off exponentially, from 1 s up to 30 s.
* There is an optional setting to slow to 0.2 Hz on metered networks
  (`connectivity_plus` is already a dependency).

**Cloud providers** have no live telemetry, so their activity comes from attribution
only (§3.3). The one exception is OpenRouter, where the upstream provider name can be shown
when Hermes reports it.

### 3.3 Attribution: what each node is doing (Hermes Desktop Gateway events)

Conduit already holds one WebSocket to the gateway: `HermesDesktopRpcClient.events`
(`packages/conduit_core/lib/features/hermes/services/hermes_desktop_transport.dart:145`),
which emits `HermesDesktopEvent {type, sessionId, payload}`. Today, the dashboard-relevant
events are either flattened or dropped. `_projectHermesTurnEvent`
(`hermes_desktop_event_projection.dart`) turns `subagent.*` into a generic
`HermesToolProgress(subagent: true)` and **throws away** `model`, `parent_id`, `depth`,
and the token counts. `moa.*` and `todo.updated` are not consumed at all.

A new **read-only tap** on the same stream (a second listener, not a change to chat
projection) consumes these events:

| Event | Payload fields used | Source |
| --- | --- | --- |
| `session.info` | `model`, `provider` (for example `custom:<name>`), `running`, `turn_started_at`, `title`, `usage` | `tui_gateway/server.py:2046` |
| `message.delta` / `reasoning.delta` | Delta length → main-agent token flow (Hub → Client, and main node → Hub) | existing |
| `tool.start` / `tool.complete` | Current tool, for the task panel | existing |
| `subagent.start/thinking/tool/progress/complete` | `subagent_id`, `parent_id`, `depth`, `goal`, `model`, `input_tokens`, `output_tokens`, `reasoning_tokens`, `api_calls`, `status`, `duration_seconds`, `task_index/task_count` | `tui_gateway/tool_progress.py:362` (`_SUBAGENT_FIELDS`) |
| `moa.reference` / `moa.progress` / `moa.aggregating` / `moa.phase` | `label`, `index/count`, `refs_done/refs_total`, `aggregator`, `phase` | `tool_progress.py:300-345` |
| `todo.updated` | Full todo snapshot | `tool_progress.py:288` |
| RPC `subagent.list` | Snapshot reconcile on open/reconnect: `subagent_id`, `parent_id`, `depth`, `goal`, `model`, `status`, `tool_count`, `last_tool` | `tui_gateway/methods_subagents.py` |
| RPC `session.active_list` | Which live sessions exist and are running | `methods_session.py:914` |
| RPC `session.usage` | Authoritative token totals per session | `methods_session.py:1168` |

**Attribution rules (pure function, unit-tested):**

1. **Main agent:**
   * A `custom:<name>` provider maps to the endpoint `<name>` from
     `/api/providers/custom-endpoints`, then to that endpoint's host, then to its node.
   * A cloud provider ID maps to that provider's cloud node.
2. **Subagent:**
   * Payloads carry `model` but **not** `provider` or `base_url`. If `delegation.provider`
     or `delegation.base_url` is configured, use it.
   * Otherwise the subagent inherits its parent's node.
   * If `model` matches exactly one engine's model ID, that engine wins.
   * If it is still ambiguous, correlate with telemetry: the local engine whose slot went
     busy within ±1.5 s of `subagent.start`.
   * Failing all of that, draw a dashed "unattributed" leader line to the Hub.
3. **MoA:** reference and aggregator slots from `/api/model/moa` map to nodes using rule 1.
4. **Cloud rate estimation:**
   * The main agent's rate is the EWMA of `message.delta` characters ÷ ~4 chars per token.
     It is corrected when `session.usage` arrives.
   * A subagent's rate is Δ`output_tokens` between `subagent.progress` frames.
5. **Untracked:** local telemetry activity that no attributed work explains becomes
   "untracked work" on that node.

**Degraded modes:**

* **Responses-API mode** (`HermesBackendMode.responsesApi`): no gateway socket. The view
  shows only the main model's node from `/v1/models`, plus Conduit-started runs from
  `hermes.tool.progress`. A banner explains that full detail needs Desktop Gateway mode.
* **No Hermes connected:** an empty state with a link to Hermes settings.

---

## 4. Architecture

The work follows the repo's extraction rule. Logic lives in the **Flutter-free core
package**, and the app holds only widgets. `tool/check_package_boundaries.dart` and CI
enforce this.

### 4.1 Core: `packages/conduit_core/lib/features/compute_dashboard/`

```
models/
  compute_node.dart            ComputeNode {id, kind: localMachine|cloud, label, host?,
                               engines: List<ComputeEngine>, accent?}
  compute_engine.dart          ComputeEngine {id, baseUrl (Hermes view), probeUrl (phone
                               view), modelIds, totalSlots?, hasMetrics, state}
  compute_sample.dart          Raw probe sample {engineId, at, slots[], metrics?, health}
  compute_activity.dart        Attributed activity {nodeId, source: main|subagent|moa|
                               untracked, label, genTps, promptTps, tokens}
  collective_task.dart         Task panel state (title, prompt, status, todos, subagents,
                               moa progress, elapsed)
  compute_snapshot.dart        Immutable frame-ready snapshot: nodes + live stats, edges +
                               flow rates, task, generatedAt
services/
  prometheus_text_parser.dart  Minimal exposition-format parser (gauge/counter lines,
                               labels, ignores HELP/TYPE)
  llama_cpp_probe.dart         Dio client per engine; health/props/models/slots/metrics;
                               router-mode aware; defensive parsing across versions
  node_inventory_service.dart  Hermes REST inventory + manual overrides → List<ComputeNode>
  manual_node_store.dart       Non-secret overrides in prefs; API keys in secure storage
                               (same split as direct_connection_profile_store.dart)
  hermes_compute_event_tap.dart  Listens to HermesDesktopRpcClient.events; projects the
                               §3.3 events into typed ComputeHermesEvent values; RPC
                               reconcile (subagent.list, session.active_list) on connect
  compute_attribution.dart     Pure §3.3 rules
  compute_aggregator.dart      Pure reducer: (snapshot, sample|event, now) → snapshot;
                               EWMA, decay, slot-task tracking; uses package:clock
providers/
  compute_dashboard_providers.dart
                               Riverpod (non-Flutter `riverpod` import, like the rest of
                               core). autoDispose: polling starts on first listener and
                               stops when the page leaves. Emits snapshots at ≤ 4 Hz.
```

**Hermes service additions** (small and contained):

* `hermes_desktop_api_service.dart`: add typed getters for `/api/model/info`,
  `/api/model/auxiliary`, `/api/model/moa`, `/api/providers/custom-endpoints` and
  `/api/system/stats`. Add `/api/model` and `/api/providers` to
  `_isProfileScopedRestPath`.
* Expose a capability flag (for example `supportsComputeDashboard`) driven by the desktop
  contract and a probe of the new endpoints. It goes through `hermes_capabilities.dart`.
* **Do not** change `_projectHermesTurnEvent`. The tap is additive, so chat rendering
  stays exactly as it is.

### 4.2 App: `lib/features/compute_dashboard/`

```
views/
  compute_dashboard_page.dart  Scaffold via the platform_ui facade; network/list toggle;
                               summary strip; task sheet
  compute_node_settings_page.dart  Per-engine probe URL / API key / name / colour
widgets/
  network_layout.dart          Pure: (nodes, size) → positions + edge curves (unit-tested)
  network_canvas.dart          One CustomPainter + one Ticker; hit-testing for taps;
                               RepaintBoundary; Semantics overlay
  token_particles.dart         Fixed-size particle pool (≤ 400), spawn from edge rates,
                               advanced in the painter. No per-frame allocations.
  node_glyph.dart              Painting helpers: ring gauge, glow, cloud glyph, badges
  node_detail_sheet.dart
  task_panel.dart
  summary_strip.dart
  compute_node_list.dart       Accessible list alternative
```

### 4.3 Routing and entry points

* **Route:** add `Routes.hermesCompute = '/profile/hermes/compute'` in
  `packages/conduit_core/lib/navigation/routes.dart`, following `hermesJobs` and
  `hermesMcp`. Register it in `lib/core/router/app_router.dart`.
* **Entry points:**
  1. A "Compute dashboard" row in Hermes settings (`lib/features/hermes/views/hermes_settings_page.dart`).
  2. A header action in the Hermes sessions tab (`lib/features/hermes/widgets/hermes_sessions_tab.dart`).
  3. An optional small "collective live" pill in the chat app bar while a Hermes turn is
     running. Tapping it opens the dashboard.
* **Android gating:** entry points render only when `defaultTargetPlatform ==
  TargetPlatform.android`. The route redirects elsewhere so a deep link cannot open it.
* **No new sidebar tab.** `SidebarTabDescriptor` requires SF Symbols and native tab-bar
  assets, which would mean iOS work.

### 4.4 Rendering and performance

* There is **one** `Ticker` for the canvas. It is muted with `TickerMode` when the route
  is covered, and stopped on `AppLifecyclePhase.paused`.
* The canvas repaints every frame only while some edge has a non-zero rate. When all nodes
  are idle it paints once and stops, the same idea as the low-frequency
  `ConduitStreamingOrbit` (`lib/features/chat/widgets/conduit_streaming_orbit.dart`).
* Snapshots arrive at ≤ 4 Hz. The painter interpolates node glow and rates between
  snapshots, so data updates never trigger widget rebuilds or layout.
* Edge paths are cached per layout. Particles hold a `t ∈ [0,1]` on a cached path.
* **Budget:** under 4 ms of UI-thread work per frame on a mid-range ARM phone (Pixel 6a
  class), with 10 nodes and 3 active edges. Check with `flutter run --profile` and
  `lib/platform/frame_profiler.dart`.

---

## 5. Implementation phases

Each phase ends green on `flutter analyze`, `dart run tool/run_test_shards.dart`,
`dart tool/platform_ui_lint.dart`, `dart run tool/check_package_boundaries.dart`, and
the ARB validators.

### Phase 0: Contract spike (≈1 day)

* Run `llama-server` (one plain instance, one in router mode, one with `--api-key`)
  against an Android ARM emulator or device on the same LAN.
* Record real `/slots`, `/metrics` and `/props` bodies as test fixtures.
* Confirm which endpoints need the API key when `--api-key` is set.
* Connect to a real Hermes Desktop Gateway. Record `session.info`, `subagent.*`, `moa.*`
  and `todo.updated` frames from a delegated task and from an MoA turn into fixtures.
* Confirm the new REST endpoints exist at the `hermes-src` commit Conduit targets.
  Record the minimum Hermes version.
* **Exit:** a fixtures directory and a short notes section appended to this file.

### Phase 1: Core data layer, no UI (≈3–4 days)

* Models, `prometheus_text_parser`, `llama_cpp_probe`, `node_inventory_service`,
  `manual_node_store`, `hermes_compute_event_tap`, `compute_attribution`,
  `compute_aggregator`, providers.
* Hermes service REST getters and the capability flag.
* **Exit:** unit tests cover parsing (all fixture shapes), rate derivation (counter
  deltas, `n_decoded` with task changes, decay), grouping by host, every attribution rule
  including the ambiguous and untracked cases, and polling lifecycle (starts on listen,
  stops on dispose or pause, backoff).

### Phase 2: Static network view (≈3 days)

* `network_layout`, `network_canvas` (nodes, edges and highlight states, no particles
  yet), summary strip, node detail sheet, task panel, list view, node settings page.
* Route, entry points and Android gating.
* Localised strings: add keys to `lib/l10n/app_en.arb`, each with an `@key` description,
  and mirror them in all 14 locales.
* **Exit:** widget tests cover layout stability, highlight states, semantics labels, the
  empty, degraded and offline states, and gating that hides the feature off Android.

### Phase 3: Live animation (≈2–3 days)

* Particle system, direction and colour rules, rate-to-spawn mapping, interpolation, the
  reduce-motion fallback, and the idle-stop optimisation.
* **Exit:** a profile-mode run on device meets the §4.4 budget. Widget tests show the
  ticker stops when idle, on pause, and under reduce motion.

### Phase 4: Collective specifics (≈2–3 days)

* Subagent satellites and leader lines, MoA fan-out and aggregator transitions, todo
  list, the multi-session chip row, "untracked work", and OpenRouter upstream labels.
* Reconcile on reconnect and resume (`subagent.list`, `session.active_list`), using the
  existing `_reconcileForeground` hook as the trigger.
* **Exit:** fixture-replay tests that feed the recorded Phase 0 event streams through the
  tap and aggregator, and assert the snapshot sequence.

### Phase 5: Stretch (optional, Android-native)

* **Ongoing notification** while a Hermes turn runs, for example "Collective · 3 nodes ·
  142 tok/s". It reuses the existing foreground-service channel in
  `android/app/src/main/kotlin/app/cogwheel/conduit/BackgroundStreamingHandler.kt`,
  updates at most every 2 s, and is off by default.
* **Home-screen widget** showing active nodes and tok/s, alongside
  `ConduitWidgetProvider.kt`.
* **Upstream Hermes PR** adding `provider` and an endpoint ID to `subagent.*` payloads.
  That removes the attribution heuristics in §3.3 rule 2.
* **Optional per-node GPU telemetry.** The user would enter a Prometheus URL for
  `node_exporter`, DCGM or an `nvidia-smi` exporter, and the node would show GPU and VRAM
  use. llama.cpp itself does not expose GPU utilisation.

---

## 6. Testing

* **Core unit tests:** `packages/conduit_core/test/features/compute_dashboard/`.
  * `package:checks` and `mocktail`.
  * `fake_async` and `clock` for EWMA, decay, backoff and polling.
  * Dio mocked at the adapter level for probes.
  * Fixtures from Phase 0 under `test/fixtures/compute_dashboard/`.
* **Widget tests:** `test/features/compute_dashboard/`. Cover layout, semantics, reduce
  motion, gating, and the sheets.
* **Manual matrix:** Android ARM emulator plus one physical device.
  * 1 Hub + 2 llama.cpp machines (one in router mode, one with `--metrics` off) + 1 cloud
    provider.
  * Delegated task with 2 subagents.
  * MoA turn.
  * Hub restart, Wi-Fi loss, app backgrounded mid-turn, light/dark, TalkBack, and reduce
    motion.

---

## 7. Android specifics

* **Android is the only target.** The code still uses the shared `platform_ui` facade,
  because CI enforces the seam on every file. iOS behaviour is left undefined, and entry
  points are hidden off Android.
* **Networking:** the phone talks straight to llama.cpp hosts on the LAN or Tailscale.
  Cleartext is already allowed, and self-signed TLS is opt-in per engine. No new
  permissions are needed (`INTERNET` is already declared).
* **Lifecycle:** polling and the ticker stop on `paused`/`hidden`. Nothing runs in the
  background unless the Phase 5 notification is turned on.
* **Battery:** one shared Dio pool, ≤ 4 concurrent requests, a metered-network slow mode,
  and no wakelocks.

---

## 8. Security and privacy

* **llama.cpp `/slots`** can include sampling params, and on some versions prompt text.
  The probe reads **numeric and state fields only**. Raw bodies are never logged or
  persisted. Diagnostics go through `DebugLogger` with the scope `compute/probe` and IDs
  only.
* **Engine API keys** live in secure storage only. They are added to the
  sensitive-values sanitiser, using the same pattern as `directProfileSensitiveValues`
  and `HermesConfig.sensitiveValues`.
* **`/api/config/raw` returns the whole Hermes YAML, which may hold inline API keys.** It
  should be used only if delegation routing cannot be read any other way. If it is used:
  parse it in memory, pull out only `delegation.{provider,model,base_url}`, drop the rest
  immediately, and never cache or log it. The better fix is the Phase 5 upstream field.
  A second option is an RPC `config.get` on the delegation keys
  (`tui_gateway/methods_config.py`).
* **Traffic stays local.** The only new network traffic goes from the phone to hosts the
  user's Hermes config or the user listed. Nothing goes to third parties.

---

## 9. Risks and open questions

| Risk | Mitigation |
| --- | --- |
| Hermes's `base_url` is `localhost`, which the phone cannot reach | Per-engine probe URL override (§3.1). The setup sheet suggests the Hub's host with the same port. |
| Subagent payload has no provider or endpoint | Heuristics plus telemetry correlation now; upstream field later (Phase 5). |
| The socket only carries events for sessions this client is attached to; cron jobs and other clients are invisible | Local nodes still light up from telemetry ("untracked"). Cloud-only background work is not visible, and the UI says so. |
| Cloud tok/s is estimated, not measured | Mark it "≈" in the detail sheet and correct it from `session.usage`. |
| llama.cpp `/slots` and `/metrics` shapes differ across versions | Defensive parsing and fixture tests per version. Missing fields degrade to "active / idle" only. |
| Responses-API mode has much less data | A clear degraded-mode banner, plus a link to switch the connection to Desktop Gateway. |
| Animation cost on low-end devices | Idle-stop, a particle cap, a reduce-motion path, and an automatic drop to reduced particles if frame time is over budget. |

**Questions for you:**

1. **Entry point.** Is Hermes settings plus the Hermes tab header enough, or should the
   dashboard be a first-class destination (for example a FAB or a launcher shortcut via
   `quick_actions`)?
2. **Multiple Hubs.** If several Hermes connections are saved, should the dashboard show
   only the active Hub, or merge every Hub into one network?
3. **GPU stats.** Do your llama.cpp machines already run a Prometheus exporter for
   GPU/VRAM? If so, the optional GPU telemetry in Phase 5 could move into Phase 2.
4. **Token text.** Should particles on the Hub → You edge carry real token text from
   `message.delta` (small glyph chips), or stay abstract dots?
