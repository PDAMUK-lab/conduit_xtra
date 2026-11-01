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
- **M4.2 (Ops v1):** doctor, security audit and backup spawn background actions
  and poll `/api/actions/{name}/status` ({name,running,exit_code,pid,lines});
  the checkpoint inventory (sessions/files/bytes) can be pruned behind a
  destructive confirmation; hooks are listed with their approval state.
  There is **no restore route** in the dashboard — restore stays a CLI job
  (`hermes checkpoints`), documented rather than faked.
- **Run now: a timeout is not a failure.** The trigger waits for the refreshed
  job, so a long run can outlive the client's timeout after the server has
  already claimed it. That is now treated as started (and the list/runs
  refreshed) instead of "Could not run scheduled job"; a real refusal keeps
  the server's own detail, which the jobs page used to swallow in `catch (_)`.
  Reproduced server-side with a throwaway no-agent job: the route fired and
  returned the refreshed job, so the endpoint itself is healthy.
- **Pull-to-refresh on detail pages.** `UtilityPageScaffold.settings` had no
  refresh indicator at all, so a pull did nothing on every settings page. The
  scaffold takes an optional `onRefresh` and wraps its list; Local models,
  Messaging, Ops, Blueprints, Config and Git now invalidate their providers on
  a pull. A widget test asserts no indicator without the callback and that a
  fling fires it once.
- **Session search.** The hub gains a Search tile backed by the server's FTS
  endpoint (`/api/sessions/search`), which the app had never called: results
  reuse `HermesSessionSummary.fromJson` (id/session_id, title, preview, source)
  and open straight into the conversation. Measured live: 20 rows for
  "hermes" with titles and previews.
- **Health strip.** One line at the top of the hub from `/api/status`:
  gateway up/stopped, version, free disk, active sessions, and `degraded` when
  the server says so. Measured: `degraded · v0.22.5 · 325 GB free` on the
  throwaway instance, which has no gateway.
- **Fleet actions.** A peer may declare `ssh_target`, `ssh_key`,
  `raise_command` and `release_command`; the page then offers Raise (when the
  peer is down) or Release (when it is up), behind a confirm. The server runs
  that peer's own command over SSH — the request names a peer and a verb, never
  a command — with one attempt and a 45 s bound; peers without both refuse
  (409). Verified with a monkeypatched runner: argv carries the configured
  command and the key, 400/404/409 on bad verb, unknown peer, missing config.
  Configured here for the desktop: `schtasks /run /tn llama-server` and a
  PowerShell Stop-Process.
- **Fleet peers.** `local_runtime.peers` (`{name, base_url, api_key?}`)
  declares other nodes' routers; status probes each once (1.2 s, max four,
  network only, nothing started or stopped) and returns `{name, base_url, up,
  model}`. The page shows a Fleet card: `serving <model>` or
  `asleep or unreachable`. Configured here: desktop at
  `http://20.20.0.40:8080/v1` — measured asleep on 2026-11-01 while its SSH
  answered, which is the expected resting state.
- **Local models (read-only).** The Local models page reads
  `/api/local-models/status` and `/hardware`: manager enabled/disabled, runtime
  installed and backend, tag and update, server running and its base URL,
  staged models with sizes, and GPU/VRAM/RAM. It deliberately has no
  start/stop: measured on this node the manager reports disabled with no
  runtime while the 9B worker serves on :8080 from outside it, so a start would
  spawn a second server and a stop could kill one the manager does not own.
  Measured: GTX 1070 Max-Q, 8.0 GB VRAM of which 7.2 GB in use, 5.6 GB RAM
  available of 15.5 GB. After the server fix the status reports
  `external_server: {base_url, model}` when a router this manager did not start
  answers (here `ornith-1.5-9b-heretic` on :8080), and the page names it instead
  of claiming the engine is stopped.
- **Backups and restore (after the server fixes).** The Ops page now
  lists the server's own backup archives from `<profile home>/backups` through
  the files API (there is no listing route). Restoring is deliberately not a
  button: `hermes import` prompts "Continue? [y/N]" and dashboard children run
  with stdin at /dev/null, so without `--force` it always aborts; with
  `--force` it then refuses while the gateway owns the profile ("Exclusive
  maintenance refused … Drain and stop the gateway"). Both measured live.
  Both blockers were then fixed server-side (operator-approved): `hermes import
  --stop-gateway` stops only the gateway this home owns and revives it via
  atexit, and `POST /api/ops/import` accepts `stop_gateway`. The app now offers
  the restore with the archive named, `import` typed to confirm, `force` always
  on (the child has no stdin for the CLI's own prompt) and the drain note that
  messaging is offline while it runs.
- **Messaging.** A Messaging page lists every channel (`GET
  /api/messaging/platforms`, 32 on this node), enabled first, with a switch
  that enables/disables one (`PUT /api/messaging/platforms/{id}`) and a detail
  sheet showing each credential's name and whether it is set — never a value.
  "Check connection" posts to `.../test` and prints the server's own verdict.
  Measured on a throwaway profile: toggling ntfy flipped state to
  `not_configured`, the check answered "Missing required setup: NTFY_TOPIC",
  and the toggle was set back off. Onboarding (Telegram/WhatsApp pairing) is
  not wired.
- **Git branches and worktrees.** The branch name in the summary opens a
  branch sheet (local first, remote after, current and default marked);
  switching asks for confirmation and shows git's own refusal when
  uncommitted changes block it. A worktrees sheet lists every checkout of the
  repo, opens one as the page's path, and removes a non-main worktree behind a
  destructive confirmation. Measured live in a scratch repo: master* → switch
  to other → back; worktree added at `<repo>/.worktrees/wt-probe` on other,
  then removed, leaving only the main checkout.
- **Blueprints.** A Blueprints page lists the server's catalog grouped by
  category (`GET /api/cron/blueprints`), with the schedule in words and a
  plugin badge. Tapping one opens a form rendered from its slots: `time`
  (HH:MM checked locally), `enum`/`weekdays` from the server's options, and
  `text`; a non-strict enum offers a custom value. `POST
  /api/cron/blueprints/instantiate` creates the job, and a 422 is shown inline
  rather than as a generic failure. Measured live: 17 blueprints;
  `morning-brief` instantiated with `23:59`/`local` produced job
  `4156e927b219` on `59 23 * * *`, then deleted (job count back to 10).
- **Scheduled agents: delivery target.** The job editor gains a "Deliver to"
  picker fed by `GET /api/cron/delivery-targets`: `local` first, then every
  configured gateway platform, with a target that has no cron home channel
  labelled as unusable instead of being offered silently. Create sends the
  chosen `deliver`; edit sends it only when the operator changed it. Measured
  live: 5 targets — local, ntfy (`NTFY_HOME_CHANNEL`), three bot-chat channels.
  The plain Open WebUI backend accepts the value and never sends it (no
  equivalent there).
- **M4.3b (Git writes):** per-file stage/unstage from the changed-file list
  (`POST /api/git/review/stage|unstage`), a commit sheet that requires a
  message and starts with "push after committing" off, and a Push action that
  only appears when the branch is ahead and asks for confirmation. All four
  routes answer `{ok:true}`. Verified end to end from the app's own service
  against a scratch repository: `M`/`?` → `A`/`A` after staging, commit
  `dddf6d8 probe commit from app service` in `git log`, tree clean after.
  Revert and branch/worktree switching are deliberately not wired.
- **M4.1 Stage B, env writes:** tapping an env key opens a sheet that writes
  one value (`PUT /api/env`) or removes the key (`DELETE /api/env`, destructive
  confirmation). Secret fields are obscured and a stored secret is only ever
  shown as the server's redacted preview; the sheet states that a write
  updates `.env` and reconciles any `config.yaml` copy of the same key. The
  list is refreshed after a write. Not yet exercised against a live `.env`:
  the endpoint is contract-verified and the sheet is widget-tested.
- **Bug: Scheduled agents opened onto a dimmed barrier.** The jobs sheet body
  grows into the space it is given (`Expanded` list), but the sheet surface
  lays content out in a shrink-wrapped column, which hands children an
  unbounded height: `RenderFlex children have non-zero flex but incoming
  height constraints are unbounded`, so the modal route rendered only its
  scrim. The sheet now sizes itself (70% of screen height, overridable), and
  a widget test drives the real `showHermesJobsSheet` route and asserts the
  content appears — it reproduced the exception before the fix. Other sheets
  using `showSurface` with flexible children should be checked for the same
  shape.
- **M4.1 Stage B (config write):** full-document editor for `config.yaml`:
  local YAML parse (must be a mapping), a line diff against the file on disk,
  the file name typed to confirm, then `PUT /api/config/raw` and a read-back.
  Verification compares **canonical** documents, because the server
  re-serialises from its parsed form (comments dropped, quoting normalised) —
  the page says so before the editor. The pre-save text is kept so the Config
  page can offer "restore previous version", itself diffed and confirmed.
  Measured live: 9,414 characters round-tripped to the same document; the file
  is rewritten on save, and a custom `HERMES_HOME` is not an isolated home for
  config endpoints (it resolves to the default profile), so the test wrote the
  real file once — restored byte-identically and verified (doctor: v52, no
  deprecated keys).
- **Ops blocker (server, 0.22.5):** `POST /api/ops/*` fails at spawn with
  `agent.secret_scope.UnscopedSecretError` for `DESKTOP_LLM_KEY` whenever the
  dashboard is the multiplexing process: `_profile_action_environment` calls
  `build_subprocess_env(scrub_secrets=True)` outside any profile secret scope.
  Affects the dashboard's own Ops buttons too. Reproduced in-process
  (`set_multiplex_active(True)` → raises) and the fix verified: wrapping the
  env build in `set_secret_scope(build_profile_secret_scope(home))` yields 90
  env keys. The app now surfaces the server's `detail` text instead of a
  generic failure. **Fixed and confirmed end to end:** the dashboard restarted
  onto the patch, and a Doctor run from the app wrote 7,325 bytes of real output
  (2 profiles, 3 issues) where the failure had left a 44-byte banner.
- **M4.3 (Git, read-only):** branch/ahead/behind, changed-file list with
  per-file markers, and each file's diff against HEAD. Stage, commit and
  push are not wired. Live contract: status keys exactly as modelled
  (relative file paths), `file-diff` → `{diff}`, and a non-repository
  path answers HTTP 200 `null`, which the app reads as "not a repo". The
  page starts at the enclosing repo of the agent's cwd (`/api/fs/git-root`),
  offers the repos directly inside it when that cwd is not one (measured 12
  under `/home/hermes/repos`), and keeps the path editable.

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
