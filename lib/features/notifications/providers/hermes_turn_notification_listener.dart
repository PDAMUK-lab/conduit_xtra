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

/// Alerts when a Hermes turn finishes while the app is not in front.
///
/// This sets a sink that the live runtime calls from its own event handler — the
/// code that provably runs, because the transcript updates. An earlier version
/// subscribed to `transcriptChanges` on the service from `hermesApiServiceProvider`
/// and never fired: the UI and the provider can hold different instances of the
/// same service, so it listened to a stream nobody was feeding.
///
/// The runtime only calls the sink when it is not foregrounded, so a turn the user
/// is watching never alerts.
final hermesTurnNotificationListenerProvider = Provider<void>((ref) {
  // `watch`, not `read`: this provider is instantiated during startup, when the
  // saved Hermes config may not have loaded yet.
  ref.watch(hermesConfigProvider);
  final router = ref.watch(notificationRouterProvider);
  final lifecycle = ref.watch(appLifecycleProvider);

  var foreground = lifecycle.current == AppLifecyclePhase.resumed;

  final lifecycleSubscription = lifecycle.changes.listen((phase) {
    foreground = phase == AppLifecyclePhase.resumed;
  });

  // Installed unconditionally and gated at call time. Installing it only when the
  // saved config looked ready was a trap: this provider is read once at startup,
  // before the config loads, so the sink stayed null forever and every alert was
  // dropped silently.
  HermesBackgroundAlerts.onReplyReady = (storedId) {
          final live = ref.read(hermesConfigProvider);
          // ignore: avoid_print
          print('HERMES_SINK called stored=$storedId enabled=${live.enabled} mode=${live.mode} fg=$foreground');
          if (!live.enabled || live.mode != HermesBackendMode.desktopGateway) {
            return;
          }
          // print(), not DebugLogger: DebugLogger writes nowhere visible on the
          // device (no logcat line, no file), so it could never be diagnosed.
          // ignore: avoid_print
          print('HERMES_ALERT_SINK fired stored=$storedId foreground=$foreground');
          // ignore: avoid_print
          print('HERMES_ALERT_SINK gate: about to route');
          if (foreground) return;
          unawaited(
            router
                .route(
                  AppNotification(
                    kind: NotificationKind.chatCompletion,
                    title: 'Hermes',
                    body: 'Reply ready',
                    sourceId: storedId,
                    dedupKey:
                        'hermes-turn:$storedId:${DateTime.now().millisecondsSinceEpoch}',
                  ),
                  alert: true,
                )
                // `then` rather than `catchError`: the handler must return a
                // NotificationSurface for `catchError`, and a dropped alert is
                // worth logging but not worth synthesising a fake surface.
                // The surface is the answer: `suppressed` here means a gate ate
                // the alert (master toggle, per-kind, dedup, or foreground).
                // Without this line a shut gate is indistinguishable from a
                // notification the OS dropped.
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

  ref.onDispose(() {
    lifecycleSubscription.cancel();
    HermesBackgroundAlerts.onReplyReady = null;
  });
});
