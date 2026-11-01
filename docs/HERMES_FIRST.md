# Hermes-first Android

Status: draft plan, 2026-10-31. Owner: Hermes node (`ai-node`).

## Goal

Make Conduit's Android build Hermes-first: Hermes is the default backend and the
primary home, and the app can drive a Hermes agent end to end from a phone —
watch a run, approve or deny what it asks, steer or stop it, and manage the
agent's workspace (sessions, schedules, skills, tools, files, memory, config).

Open WebUI, Direct and Ollama stay as secondary backends. The fork tracks
`PDAMUK-lab/conduit_xtra` (upstream `cogwheel0/conduit`, GPL-3.0); changes aim to
stay upstream-friendly.

## Decisions (operator, 2026-10-31)

| Question | Decision |
| --- | --- |
| Other backends | Keep, but Hermes is the default and the primary home |
| First milestone | Control-first: Hermes home/onboarding, approvals inbox, run control, sessions/jobs polish |
| Notifications | Local notifications now; the unmerged upstream push stack is revisited later |
| Device verification | Operator sideloads the APK this node builds and reports back |

## Contract baseline

- App pins `hermes-src` at `939e45c9` (Hermes **v0.21.2**, 2026-09-11).
- Node runs Hermes **v0.22.5** (2026.9.24), commit `8c698125`; the app's pin is
  an ancestor, so the node's dashboard is a superset of the pinned contract.
- Contract source of truth at runtime: `GET /api/status`, `GET /v1/capabilities`,
  and the dashboard routers under `hermes_cli/web_routers/` (**270 routes**,
  33 routers at v0.22.5).

## How the app talks to Hermes today

Measured from `packages/conduit_core/lib/features/hermes/` (~25k LOC, 40 service
files) and `lib/features/hermes/` (UI):

- Two modes (`HermesBackendMode`): `responsesApi` (OpenAI Responses gateway at
  `/v1`, API key) and `desktopGateway` (dashboard/desktop surface, auth kinds
  `legacyToken` / `nativePkce` / `dashboardCookie`).
- `desktopGateway` carries a JSON-RPC client plus REST calls to `/api/sessions`,
  `/api/cron`, `/api/mcp`, `/api/profiles`, `/api/audio`, `/api/status`.
- Dashboard-cookie auth is carried by a hidden WebView bridge
  (`hermes_dashboard_rest_session.dart`); native PKCE
  (`/auth/native/authorize|token|refresh`) and `X-Hermes-Session-Token` are
  already implemented in `hermes_desktop_auth_rest.dart`.
- Capability gates are parsed from `/v1/capabilities` (`HermesCapabilities`).
- Existing UI: Hermes tab (server sessions + scheduled-agents entry), settings
  and connection editor, jobs page/editor, MCP page, approval/decision cards,
  sessions tab.

## Coverage against the dashboard (v0.22.5)

Literal endpoint matching across the Dart sources is a lower bound only: many
calls are built dynamically or go over JSON-RPC. Feature-level status below is
the useful view.

| Dashboard surface | App today |
| --- | --- |
| Chat + streaming runs, tool activity | Yes |
| Approvals / decisions (per session) | Yes (cards in chat) |
| Sessions list, messages, rename, delete, fork | Yes |
| Scheduled jobs (list, create, edit, pause, resume, trigger, delete) | Yes |
| MCP servers (list, add, test, auth, enable, install) | Yes |
| Skills | List only |
| Toolsets | List + limited config |
| Profiles | List only |
| Models | List only |
| Health / status probe | Yes |
| Audio (transcribe, speak, voice-live) | Yes |
| Bots | Yes |
| Memory (read, provider, reset) | No |
| Files / filesystem browser | No |
| Config editor (raw), env/secrets | No |
| Analytics (usage, models) | No |
| Logs | No |
| Plugins (agent + dashboard) | No |
| Channels (WhatsApp/Telegram onboarding) | No |
| Pairing, webhooks | No |
| Ops (doctor, backup/import, checkpoints, hooks) | No |
| Git review (status, diff, stage, commit, push, PR) | No |
| Local models (status, catalog, download, server) | No |
| Delegation routing | No |
| Cron run history, delivery targets, blueprints | No |
| Workspaces, ui-preferences, curator/learning | No |

Counts: 24 of 270 dashboard routes appear verbatim in app sources; the absent
list is dominated by `ops` (28), `git` (21), `files` (19), `dashboard_ui` (18),
`local_models` (18), `status` extras (18), `profiles` CRUD (12), `tools` (12),
`messaging` (11).

## Build environment on `ai-node`

Measured 2026-10-31, unprivileged user `hermes` (no sudo):

| Component | Version | Path |
| --- | --- | --- |
| Flutter | 3.47.9 stable (Dart 3.13.7) | `~/sdk/flutter` |
| Android SDK | platform 37.0, build-tools 37.0.0 | `~/sdk/android` |
| NDK | 29.0.14206865 | `~/sdk/android/ndk` |
| JDK | OpenJDK 21.0.12 | `/usr/lib/jvm/java-21-openjdk-amd64` |
| Repo | clone of the fork, branch `hermes-first` | `~/repos/conduit_xtra` |

`flutter doctor` reports the Android toolchain green (licenses accepted). The
repo needs `git submodule update --init third_party/mermaid third_party/katex`
before `flutter pub get`.

## Current status (2026-10-31)

- **M0 verified.** `flutter build apk --debug --target-platform android-arm64`
  completed in 710 s (Gradle `assembleDebug`), producing
  `build/app/outputs/flutter-apk/app-debug.apk` — 213,263,672 bytes,
  sha256 `ba1d88ff8629360d54a49d28713ad32bb1278e1a01a65df72d35f11f3b7c8887`,
  package `app.cogwheel.conduit.debug` (installs beside a Play build),
  versionName 4.2.1, compileSdk 37, targetSdk 36.
- **M1 shipped** in `ef8f9203` on `hermes-first`: Hermes-first chooser,
  Hermes tab leads the sidebar, Approvals inbox across sessions, pending-store
  listing + change stream. `flutter analyze`: no issues; the new store and page
  tests plus the chooser accessibility/order tests pass.
- **M1.5 (local notifications + inbox stop):** a backgrounded approval posts an
  OS notification through the shared router (new `NotificationKind.hermesApproval`,
  tap opens the inbox), primed so an old approval does not alert on launch, and
  each inbox card can stop the waiting run (`session.interrupt`) behind a
  confirmation. Router tests cover system/banner/suppressed/replay paths.
- Still a local listener: it only sees events while the app process is alive.
  Runs that raise an approval while the app is killed need the push stack.
- **M2.1 (Skills):** browse (search, category, enabled state), enable/disable,
  rewrite SKILL.md, and create a skill — through the dashboard's own
  `/api/skills*` contract, verified with recorded-request tests plus a live
  curl probe against Hermes 0.22.5 (88 skills, 33 disabled). Skills tile sits
  in the Hermes tab; editor routes under `/profile/hermes/skills`.
- **M2.2 (Memory, corrected):** the Memory tab now opens the **Memory Wiki**
  plugin surface (subjects, daily logs, persistent MEMORY.md/USER.md entries,
  provider archive) from `/api/plugins/memory-wiki/*`; the provider form moved
  to `/profile/hermes/memory/settings`. Validated against the live payload
  (50 subjects, 22 days, 12/13 entries).
- **M3.1 (Files):** browser over `/api/fs` (list, default-cwd, read-text,
  write-text, git-root), text editor with a client-side stale check; binary
  and truncated previews are read-only. Live contract probed on a gated
  0.22.5 dashboard (30 entries, YAML/Dart reads, EACCES and 404 paths).
- **M3.2 (Toolsets):** list with enable/disable, per-toolset provider choice
  (with env keys shown as set/missing, never values) and model choice.
  Contract extracted by the laptop pool and verified against
  `tools.py` (12/12 routes, request models and response keys) and a live
  gated dashboard (27 toolsets, 16 providers, `needs_auth` status).
- **M3.3 (Profiles):** list with model, default/active/gateway state and skill
  count; per-profile SOUL.md editor, description, main model
  (provider + id) and a set-active action. Rename/delete/export/import
  are deliberately left to a desktop. Contract table delegated to the
  laptop pool and checked against both routers in `profiles.py`
  (16 + 4 = 20 routes; the first count missed `sessions_router`).
- **M3.4 (Cron depth):** audited, not rebuilt — the app already lists runs
  (`/api/cron/jobs/{id}/runs`) and shows state/delivery/last/next run.
  Blueprints and delivery-target pickers are deferred to the end of M3.
- **M3.5 (Analytics + Logs):** read-only usage/model aggregates with a
  7/30/90-day switch, and a 500-line log tail with file/level/search
  filters. Live shapes confirmed on a gated 0.22.5 dashboard
  (`{daily,by_model,by_task,totals,period_days,skills,tools}`,
  `{models,totals,period_days}`, `{file,lines}`, 400 on unknown file).
- **M4.1 Stage A (Config + env, read-only):** the whole `config.yaml` with its
  path, and every env key with its redacted value, description and
  category — search plus a "set only" default. Measured live: config
  `{yaml,path}`, env a 406-key map whose rows carry `is_set`,
  `redacted_value`, `is_password`, `channel_managed`, `custom`.
  Writes (`PUT /api/config/raw`) are deliberately not in this build:
  the server replaces the whole document (`merge_existing=False`).

## APK delivery to the NAS

Every file that lands in `build/app/outputs/flutter-apk/` is mirrored to the
NAS `hermes` share by a user service, so a build is installable from the phone
without touching this node.

- Source: `scripts/publish-apk-to-nas.sh` (manual runs are safe and idempotent);
  watcher: `scripts/watch-apks.sh`, run by `~/.config/systemd/user/apk-publish-watcher.service`
  (enabled, linger on, 5 s poll, `NRestarts=0`).
- Destination: `//20.20.0.10/hermes` → `conduit/apks` (mounted at `/srv/share`).
- Each build: `conduit-hermes-<version>-<commit>-<sha8>.apk` plus `.sha256`.
- `latest.txt` names the newest build and carries its sha256, size, version,
  commit and build/publish timestamps — a pointer, not a second copy.
- Retention: the newest 10 content builds; only files matching this
  publisher's own `conduit-hermes-*.apk` pattern are ever deleted.
- Log: `~/.hermes/logs/apk-publish.log`. State: `~/.hermes/state/apk-publish.state`
  (mtime+size per APK, so an unchanged build costs a `stat` and nothing else).

Verified 2026-10-31: build #3 (286,413,184 bytes, sha256 `41b530b7…`) published,
checksum re-read from the NAS matched, deleting the NAS copy and touching the
APK republished it in 7 s, and an idle watcher added no log lines.

## Milestones

**M0 — build pipeline (this session).** Flutter 3.47.9 + Android SDK 37 + NDK
29.0.14206865 provisioned under `~/sdk`; `flutter pub get`, codegen, analyze,
test shards, `flutter build apk --debug --target-platform android-arm64`.
Artifact handed to the operator. No source changes.

**M1 — Hermes-first control surface.** Hermes first in onboarding and as the
landing tab; approvals inbox across sessions with inline approve/deny and
tap-through; run control (stop/interrupt, open to steer/resume); local
notification when an approval is waiting while the app is backgrounded.
Sessions/jobs polish.

**M2 — workspace parity pack.** Memory, files browser (list/read/write/download),
skills content/toggle/create, toolsets config (model/provider/env), profiles
CRUD + soul, models (set/MoA/auxiliary), analytics (usage/models), logs tail,
cron run history + delivery targets + blueprints.

**M3 — admin parity pack.** Config raw editor, env/secrets, plugins, pairing,
webhooks, ops (doctor/backup/checkpoints/hooks), git review, local models,
delegation routing, channels/workspaces/ui-preferences that make sense on a
phone.

**M4 — release.** Signed APK, branding for the Hermes-first build, docs,
upstream-compatible PR series.

## Verification

- `dart run build_runner build` (app + `packages/conduit_core`)
- `flutter analyze --no-fatal-warnings --no-fatal-infos`
- `dart run tool/run_test_shards.dart` (Hermes tests: 373 files)
- `flutter build apk --debug --target-platform android-arm64`
- Per feature: widget/unit tests plus a live probe against a throwaway Hermes
  dashboard on `127.0.0.1:9120` with a known session token.
- On device: operator installs the APK, reports what works.

## Constraints and gotchas

- New UI strings must exist in all 14 `lib/l10n/app_*.arb` locales
  (`tool/validate_arb_locales.dart` fails otherwise); add English text to every
  locale until translations land.
- The workspace uses a single lockfile; members stay `resolution: workspace`.
- `android/app/build.gradle.kts` pins `compileSdk = 37`, `ndkVersion
  29.0.14206865`, and ships `armeabi-v7a` + `arm64-v8a` only.
- Reports must name the artifact a number came from; no unverified claims.
