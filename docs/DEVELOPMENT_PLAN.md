# Conduit Hermes-first — development plan (M3 → M6)

Status: **plan only, 2026-10-31. Nothing in this document has been started.**
Owner: Hermes node (`ai-node`). Implementation: planner only (see §2).

This plan covers everything after the shipped M1/M1.5/M2.1/M2.2 work
(Hermes-first shell, approvals inbox + stop, local approval notifications,
Skills, Memory). It is written to be executed slice by slice, each slice
ending in a verified APK on the NAS.

## 1. Ground rules

1. **Contract first.** No client code before the endpoint's real request and
   response have been measured with `curl` against a throwaway Hermes
   dashboard, and the measured sample is stored as a fixture.
2. **A slice is shippable.** Analyze clean, targeted tests, APK built,
   checksum re-read from the NAS, and one on-device check by the operator.
   A green command is not evidence the file landed.
3. **Read before write; safe writes before destructive ones.** Destructive or
   privileged actions (memory reset, config/env writes, toolset env, git push,
   checkpoint restore) need a typed confirmation and a capability gate.
4. **l10n is part of the slice.** Every new string lands in all 14
   `app_*.arb` files, `flutter gen-l10n`, and the validator passes.
5. **Version gates.** The app's pinned contract is Hermes 0.21.2; the node runs
   0.22.5. A surface that does not exist on the connected server shows a
   capability message, never a crash.

## 2. Who does what (fleet delegation)

Measured 2026-10-31: laptop worker up (`127.0.0.1:8080`, 9B), desktop worker
**down** (`20.20.0.40:8080` unreachable — must be raised first), remote pool
available (`deepseek-v4.1-flash`). Pools are `laptop`, `desktop`, `remote`;
4 concurrent children.

**Only the planner implements.** Nodes get *research and drafting* tasks whose
output is a document the planner re-checks against the source. Nodes never
edit the repo, never run builds, never choose architecture.

| Allowed to nodes | Never delegated |
| --- | --- |
| Extract endpoint shapes/fields from vendored server source into a table | Writing Dart services, models, pages, routes |
| Draft ARB translations for a fixed English key list | Choosing UX, routes, or data models |
| Generate fixture JSON from a provided sample | Editing the repo or running builds |
| Read a TSX page and list its controls/behaviour | Deciding what to implement, or verification |
| Cross-check the app's existing calls against a route inventory | Anything touching secrets, signing, or the live node |

Verification protocol for every delegated artifact: the planner re-derives it
from the source (diff or re-run), rejects anything that does not match, and
records the node and prompt used in the slice's notes. A node result is a
*claim* until the planner reproduces it.

## 3. Slice order

| # | Slice | Surface (measured routes) | Size | Depends on |
| --- | --- | --- | --- | --- |
| 3.1 | Files | 19 `/api/fs*` + `/api/files*` | L | dashboard restart (§4) |
| 3.2 | Toolsets | 12 `/api/tools*` | M | 3.1 patterns |
| 3.3 | Profiles & soul | 16 `/api/profiles*` | M | — |
| 3.4 | Cron depth | 13 `/api/cron*` | S–M | 3.3 (profile scoping) |
| 3.5 | Analytics + Logs | 4 analytics + `/api/logs` | S | — |
| 4.1 | Config & env (staged) | 11 `/api/config*`, `/api/env*` | L | 3.5 (logs for errors) |
| 4.2 | Ops & checkpoints | 28 `/api/ops*`, actions | L | 4.1 (restart UX) |
| 4.3 | Git review | 21 `/api/git*` | M–L | 4.2 (safety UX) |
| 5 | Push notifications | none (12 unmerged PRs) | XL | decision gate |
| 6 | Release hardening | — | M | all above |

Order rationale: read-only first, then small writes, then privileged writes;
Files before Toolsets because both reuse the same list/editor widgets; Git
last among the writes because a mistaken push cannot be undone locally.

## 4. Prerequisite before 3.1

The live dashboard booted at 02:10 while the checkout moved at 02:26/02:54, so
its `model.options` refuses with code-skew 5098 (the app now tolerates it, the
web UI does not). Restart `hermes-dashboard` before live contract probing, or
probe on a throwaway dashboard (`--port 912x`, its own `HERMES_HOME`, basic
auth, then deleted) as done for Skills/Memory.

## 5. Slice specifications

Each slice lists: contract to measure, core work, UI, tests, delegation, exit.

### 3.1 Files (L)
- Contract: `GET /api/fs/list?path=`, `GET /api/fs/read-text`, `POST /api/fs/write-text`,
  `GET /api/fs/download`, `GET /api/fs/git-root`, `GET /api/fs/default-cwd`,
  `GET /api/files`, `POST /api/files/upload` (probe only; upload may stay out).
- Core: `HermesFileEntry` model (name, path, kind, size, mtime), directory
  listing with bounded entries; text read with a size cap (~256 KB) and UTF-8
  validation; write = full rewrite with expected-mtime conflict check if the
  server exposes it; download to the share sheet.
- UI: files page from the Hermes tab (start at `default-cwd`, breadcrumb, git
  root shortcut), text viewer/editor, "open in…" download.
- Tests: path traversal rejection, size cap, non-UTF-8 fallback, conflict.
- Delegation: laptop — list the JSON fields per endpoint from the vendored
  server source; desktop — cross-check every `/api/fs*` route against
  `hermes_cli/web_routers/files.py` for auth/profile requirements.
- Exit: browse a real repo on the node, open a file, save a one-line change,
  re-read it from the node; APK on NAS.

### 3.2 Toolsets (M)
- Contract: `GET /api/tools/toolsets`, `PUT /api/tools/toolsets/{name}`,
  `GET .../config`, `GET .../models`, `PUT .../model`, `.../provider`, `.../env`,
  `POST .../post-setup`; terminal backend and computer-use status as read-only.
- Core: toolset model (enabled, model, provider, env keys), env values masked
  with explicit reveal; write paths profile-scoped.
- UI: toolsets list with enable switch and a detail sheet (model/provider/env).
- Tests: masked env never logged, empty env removals, refusal surfaces.
- Delegation: laptop — extract the env key rules from server source; desktop —
  produce a test matrix of enable/disable × model/provider × env.
- Exit: switch a toolset's model, disable and re-enable it, confirm agent-side.

### 3.3 Profiles & soul (M)
- Contract: `/api/profiles` CRUD, `/active`, `/soul` GET/PUT, `/description`,
  `/model`, `/export`, `/import`.
- Core: profile model; soul editor (large text, bounded); active-profile switch
  guarded when a run is live; export/import as file share.
- UI: profiles page (list, create, edit soul, set active).
- Tests: name validation, active switch refusal, import bounds.
- Delegation: laptop — summarise the `/soul` document rules; desktop — review
  the active-switch edge cases against the server router.
- Exit: edit `alternative`'s soul, switch back to `default`, verify per-profile.

### 3.4 Cron depth (S–M)
- Contract: `/api/cron/jobs/{id}/runs`, delivery targets, blueprints.
- Core: run detail (status, duration, output excerpt, delivery result).
- UI: expandable run history per job; delivery target display.
- Tests: pagination bounds, empty history, failed delivery copy.
- Delegation: laptop — extract run row fields; desktop — draft the failure copy
  matrix (auth, network, target missing).
- Exit: a job with two runs shows both, including a deliberate failure.

### 3.5 Analytics + Logs (S)
- Contract: `GET /api/analytics/usage?days=`, `/api/analytics/models?days=`,
  `GET /api/logs?file&lines&level&component`.
- Core: usage/cost rows; log tail with level/component filters, 500-line cap.
- UI: two read-only screens; pull-to-refresh; no writes.
- Tests: day bounds, unknown file, huge line counts clamped.
- Delegation: laptop — list analytics fields; desktop — enumerate log
  components/files from the server.
- Exit: usage totals match a dashboard screenshot; log tail streams the last
  500 lines of `agent.log`.

### 4.1 Config & env — staged (L)
- Stage A (read-only): `GET /api/config/raw`, `GET /api/env` masked,
  `GET /api/providers/custom-endpoints`.
- Stage B (writes): `PUT /api/config/raw` with a server-side validate-first
  round trip, diff view, typed confirmation; `PUT/POST/DELETE /api/env`;
  `POST /api/env/reveal` behind biometric/lock if available.
- Tests: YAML round-trip, refusal on invalid config, secret never in logs.
- Delegation: laptop — extract validation error shapes; desktop — draft the
  risky-keys list (auth, provider, update) that forces extra confirmation.
- Exit: change a harmless key (e.g. a UI preference) through the app, see the
  dashboard reflect it, then revert.

### 4.2 Ops & checkpoints (L)
- Contract: `/api/ops` (doctor, audit, backup, import, checkpoints, hooks,
  actions status). Long-running actions are background jobs — the app polls
  status and shows logs.
- Core: action model with status/log tail; checkpoint list + restore (typed
  confirmation naming the checkpoint); doctor/audit read-only.
- UI: ops page with sections; destructive actions gated.
- Tests: action polling stops on terminal state; restore confirmation.
- Delegation: laptop — map each action to its status endpoint; desktop —
  draft the checkpoint restore warning copy.
- Exit: run doctor, view its log to completion; list checkpoints (restore only
  with operator approval).

### 4.3 Git review (M–L)
- Contract: `/api/git` status/diff/stage/commit/push/PR.
- Core: status + diff viewer (read-only first), then stage/commit; push/PR
  behind typed confirmation and a branch guard.
- Tests: binary files, large diffs clamped, no-push-without-confirm.
- Delegation: laptop — extract diff payload shape; desktop — list destructive
  git operations and required confirmations.
- Exit: read status/diff of a scratch repo; commit only in a sandbox repo.

### 5. Push notifications — decision gate (XL)
Not started until local notifications have been observed in real use for a
week. Then decide: adopt the unmerged upstream stack (E2E relay, Hermes plugin,
Android decrypt) or keep local-only and rely on foreground/background socket
behaviour. Needs relay hosting + FCM credentials — an operator decision, not a
code task.

### 6. Release hardening (M)
Signed APK/appbundle (keystore generated and stored off-node), version
discipline, Obtainium/Play distribution decision, crash reporting left
local-only, and an upstream-friendly PR series against `cogwheel0/conduit`.

## 6. Verification gates (every slice)

1. Contract evidence: the measured request/response pair saved under
   `docs/contracts/<slice>/`.
2. `flutter analyze --no-fatal-warnings --no-fatal-infos` → "No issues found!".
3. Targeted tests (new + touched), then the shard runner for the slice.
4. `flutter build apk --debug --target-platform android-arm64` exit 0.
5. NAS: checksum re-read from `/srv/share/conduit/apks` matches the build;
   `latest.txt` names it.
6. On-device: operator confirms the slice's exit criterion.

## 7. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Contract drift 0.21.2 ↔ 0.22.5 | capability gate; measured contract per slice; graceful "not supported" |
| Write operations damage the node | typed confirmations; sandbox repos first; checkpoints before risky writes |
| Secrets leak through logs/UI | mask by default; reveal behind explicit action; never log env values |
| Large files / binaries over mobile | size caps, download-only for big files, UTF-8 gate |
| l10n drift | 14-locale gate in every slice |
| Node output wrong or fabricated | planner re-derives every artifact; redo or take over |
| Desktop unavailable | laptop first; heavy research waits or goes to the remote pool |
| Debug APK size variance (213 vs 286 MB observed) | investigate during 3.1; not user-visible |

## 8. Definition of done (whole plan)

Every slice in §3 shipped with the §6 gates, the plan's §7 risks closed or
accepted in writing, and a final APK whose Hermes surface covers the measured
dashboard routes except those explicitly deferred (messaging channels, local
models, dashboard plugins, push until the §5 gate).
