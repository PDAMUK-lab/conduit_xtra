import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:conduit_core/features/hermes/models/hermes_config.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_background_alerts.dart';
import 'package:conduit_core/features/notifications/models/app_notification.dart';
import 'package:conduit_core/ports/app_lifecycle.dart';
import 'package:conduit_core/providers/host_ports.dart';
import 'package:conduit_core/utils/debug_logger.dart';

import 'notification_socket_listener.dart' show notificationRouterProvider;

/// Installs the sink that alerts when a Hermes turn finishes while the app is
/// not in front, and leaves it installed for the lifetime of the process.
///
/// Deliberately **not** a `Provider`. The sign-out path runs
/// `ref.invalidate(hermesConfigProvider)`, and a provider that *watches* it is
/// disposed along with it — the dispose callback then set
/// `HermesBackgroundAlerts.onReplyReady` back to null, and nothing re-read the
/// provider afterwards. The app looked healthy (socket up, watch ticking,
/// `message.complete` arriving) while every background turn was a silent no-op.
/// Confirmed on device by reading the live static over the Dart VM service:
/// `The method 'call' was called on null`.
///
/// The sink must outlive provider invalidation, so it is installed here against
/// the container and reads current state at call time instead of capturing it.
void installHermesTurnAlertSink(ProviderContainer container) {
  // Two paths call this for the same reply: the socket's message.complete
  // handler (fast, but the frame is often dropped while the screen is off) and
  // the live-watch poll (slower, cannot be missed). They land within a second of
  // each other, so a short per-session window collapses them into one alert
  // instead of two notifications for one answer.
  final lastAlertAt = <String, DateTime>{};
  const duplicateWindow = Duration(seconds: 3);

  HermesBackgroundAlerts.onReplyReady = (storedId) {
    final live = container.read(hermesConfigProvider);
    // ignore: avoid_print
    print('HERMES_SINK called stored=$storedId enabled=${live.enabled} '
        'mode=${live.mode}');
    if (!live.enabled || live.mode != HermesBackendMode.desktopGateway) {
      return;
    }
    // Read at call time: the lifecycle the sink captured at install time goes
    // stale the moment the app is backgrounded, which is exactly when it fires.
    final foreground =
        container.read(appLifecycleProvider).current ==
        AppLifecyclePhase.resumed;
    // print(), not DebugLogger: DebugLogger writes nowhere visible on the
    // device (no logcat line, no file), so it could never be diagnosed.
    // ignore: avoid_print
    print('HERMES_ALERT_SINK fired stored=$storedId foreground=$foreground');
    if (foreground) return;
    final now = DateTime.now();
    final previous = lastAlertAt[storedId];
    if (previous != null && now.difference(previous) < duplicateWindow) {
      // ignore: avoid_print
      print('HERMES_ALERT_SINK suppressed duplicate stored=$storedId');
      return;
    }
    lastAlertAt[storedId] = now;
    unawaited(
      container
          .read(notificationRouterProvider)
          .route(
            AppNotification(
              kind: NotificationKind.chatCompletion,
              title: 'Hermes',
              body: 'Reply ready',
              sourceId: storedId,
              dedupKey:
                  'hermes-turn:$storedId:'
                  '${DateTime.now().millisecondsSinceEpoch}',
            ),
            alert: true,
          )
          // `then` rather than `catchError`: the handler must return a
          // NotificationSurface for `catchError`, and a dropped alert is worth
          // logging but not worth synthesising a fake surface. The surface is
          // the answer: `suppressed` here means a gate ate the alert (master
          // toggle, per-kind, dedup, or foreground).
          .then(
            (surface) {
              // ignore: avoid_print
              print('HERMES_ALERT_SINK surface=$surface');
            },
            onError: (Object e, StackTrace st) {
              DebugLogger.error(
                'hermes turn notification failed',
                error: e,
                stackTrace: st,
              );
            },
          ),
    );
  };

  // ignore: avoid_print
  print('HERMES_SINK installed');
}
