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
  final config = ref.watch(hermesConfigProvider);
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
          if (!live.enabled || live.mode != HermesBackendMode.desktopGateway) {
            return;
          }
          DebugLogger.info(
            'hermes reply ready: $storedId foreground=$foreground',
          );
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
                .catchError((Object e, StackTrace st) {
                  DebugLogger.error(
                    'hermes turn notification failed',
                    error: e,
                    stackTrace: st,
                  );
                }),
          );
        };

  ref.onDispose(() {
    lifecycleSubscription.cancel();
    HermesBackgroundAlerts.onReplyReady = null;
  });
});
