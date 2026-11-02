# Notifications while the phone is locked — design and first step

Status: **root cause found (2026-11-02): the router's first gate was shut.**
`AppSettings.notificationsEnabled` defaulted to `false`, and nothing ever wrote
that preference, so `NotificationRouter.route()` returned `suppressed` before it
chose any surface — for every kind, including approvals. Measured on the phone:
`FlutterSharedPreferences.xml` held no `notifications_enabled` key at all, and
`dumpsys notification` had never held a single Conduit message notification.

Fix (4.2.2, `606ed6a0`): default it `true`, ask for `POST_NOTIFICATIONS` at
startup when enabled, bring the `conduit_messages` channel up at startup
(`7060c8b1`), treat lifecycle `inactive` as backgrounded on MIUI locks, and fire
the turn alert from the live-watch poll that provably runs while backgrounded.
A regression test (`notification_router_test.dart` › `shipped defaults`) pins
the whole claim: const defaults + backgrounded ⇒ `NotificationSurface.system`.

Verified on an Android 14 emulator: startup created `conduit_messages`, the
permission sheet appeared and was granted. **Not yet verified on the phone**: it
signed itself out when the dashboard restarted (native tokens invalidated) and
MIUI blocks input injection, so re-authenticating needs the operator.

Status of the older keepalive work: **shipped and verified on device
(2026-11-02).** The phone now receives a reply while locked —
verified with the socket held open through a lock (server log: accepted 02:33:58,
still ESTAB at 02:35:41, no close event; operator confirmed the reply was waiting
on unlock). What is still missing is the lock-screen notification.

## What already works

- `HermesApprovalNotificationListener` posts a local OS notification when an
  approval or clarify prompt is waiting (`NotificationKind.hermesApproval`), and
  taps route to the approvals inbox. This fires **only while the app process is
  alive and its Hermes socket is up** — i.e. in the foreground or shortly after.
- `HermesDesktopApiService` reconnects a dead socket and reconciles the open
  session (watchdog + `resumeById`), but only while `_foreground` is true.
- Android already has a background execution service for chat/voice streams
  (`BackgroundStreamingHandler`, `PlatformBackgroundStartRequest`), with a
  persistent-notification service and wake locks.

## What is missing

1. ~~**A keepalive-only lease.**~~ **Done** (`6907aba3`): `socketKeepaliveId`
   becomes a lease of kind `socket` (Pigeon schema → Dart + Kotlin), and
   `hermesSocketKeepaliveProvider` takes it while backgrounded on a native Hermes
   conversation, releasing on resume.
   ~~Original note:~~ `BackgroundStreamingHandler.socketKeepaliveId`
   exists, but `_buildBackgroundStreamLeases()` (line 100) drops that id with a
   `where` filter, so `startBackgroundExecution([socketKeepaliveId])` produces an
   empty lease list and starts nothing. Verified 2026-11-02 by reading the
   builder: the filter is the only reason the id cannot become a lease.
   The fix is cross-language: `BackgroundStreamKind` has only `chat`/`voice`, both
   mapped to `PlatformBackgroundStreamKind`, so a socket-only lease needs a third
   kind in Dart *and* in the Kotlin service, plus a foreground-service type that
   survives with no stream. Then the lifecycle wiring (item 2) can acquire it.
2. **Lifecycle wiring.** Nothing acquires/releases that lease when the app is
   backgrounded with a Hermes connection configured.
3. **Android service mode.** The service must survive with no active stream
   (its current contract counts streams) and declare an appropriate foreground
   service type on Android 14+.

## First step (ordered)

1. Native: accept a `socket-keepalive` lease in `PlatformBackgroundStartRequest`
   and start the service in "keepalive only" mode (no stream bookkeeping, no
   microphone, low-importance persistent notification).
2. Dart: in the lifecycle observer, on `paused` with a usable Hermes config and
   a bound session, `startBackgroundExecution([socketKeepaliveId])`; on
   `resumed`, `stopBackgroundExecution([socketKeepaliveId])`. Keep it behind a
   setting while it proves itself.
3. Reconnect while backgrounded: let the live watch tick continue when the
   process is kept alive (drop the `_foreground` gate for the socket only), so
   a dropped socket is re-established and events resume.
4. Verify on the phone, which is the only place this can be proven:
   - approval arrives while the screen is locked → notification posted;
   - tap opens the approvals inbox;
   - battery impact measured over an hour idle (expected: Android's foreground
     service, no wakelock held beyond the service lifetime).

## Traps

- Do not ship this without an on-device test; a wrong foreground-service type
  or a missing `stopForeground` crashes or drains the battery.
- The earlier session-pause bug came from clients that *disconnect* under
  another runtime; a keepalive that flaps makes that worse, so this must be a
  stable long-lived socket, not a reconnect loop.
