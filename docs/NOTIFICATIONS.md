# Notifications while the phone is locked — design and first step

Status: **not implemented.** This note records what exists, what is missing, and
the exact change to make, so the work starts from evidence instead of a guess.

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

1. **A keepalive-only lease.** `BackgroundStreamingHandler.socketKeepaliveId`
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
