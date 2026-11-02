import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:conduit_core/features/hermes/models/hermes_config.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit_core/features/notifications/models/app_notification.dart';
import 'package:conduit_core/ports/app_lifecycle.dart';
import 'package:conduit_core/providers/host_ports.dart';
import 'package:conduit_core/utils/debug_logger.dart';

import 'notification_socket_listener.dart' show notificationRouterProvider;

/// Alerts when a Hermes turn finishes while the app is not in front.
///
/// Before this, a reply that landed while the phone was locked simply waited: the
/// socket was kept alive (the lease work) but nothing told the user. The kinds and
/// the router already existed for chats and channels, so this raises the same
/// `chatCompletion` kind for a Hermes transcript change.
///
/// Deliberately narrow: only while the app is backgrounded and only for a native
/// Hermes connection. A turn the user is watching fires no notification, and the
/// router's own dedup keeps one turn from alerting twice.
final hermesTurnNotificationListenerProvider = Provider<void>((ref) {
  // `watch`, not `read`: this provider is instantiated during startup, when the
  // saved Hermes config may not have loaded yet. With `read` it saw "disabled",
  // returned, and never re-ran — a listener that could never fire.
  final config = ref.watch(hermesConfigProvider);
  if (!config.enabled || config.mode != HermesBackendMode.desktopGateway) {
    return;
  }

  final lifecycle = ref.watch(appLifecycleProvider);
  var foreground = lifecycle.current == AppLifecyclePhase.resumed;

  final lifecycleSubscription = lifecycle.changes.listen((phase) {
    foreground = phase == AppLifecyclePhase.resumed;
  });

  final service = ref.watch(hermesApiServiceProvider);
  // Only the desktop-gateway service streams transcript changes.
  if (service is! HermesDesktopApiService) return;
  final router = ref.watch(notificationRouterProvider);

  final transcriptSubscription = service.transcriptChanges.listen((storedId) {
    // Foreground turns are already on screen; a locked phone is the case this
    // exists for.
    if (foreground) return;
    unawaited(
      router
          .route(
            AppNotification(
              kind: NotificationKind.chatCompletion,
              title: 'Hermes',
              body: 'Reply ready',
              sourceId: storedId,
              dedupKey: 'hermes-turn:$storedId:${DateTime.now().millisecondsSinceEpoch}',
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
  });

  ref.onDispose(() {
    lifecycleSubscription.cancel();
    transcriptSubscription.cancel();
  });
});
