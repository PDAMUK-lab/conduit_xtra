import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:conduit_core/features/hermes/models/hermes_config.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_pending_decision_store.dart';
import 'package:conduit_core/features/notifications/models/app_notification.dart';
import 'package:conduit_core/utils/debug_logger.dart';

import '../../../core/utils/current_localizations.dart';

import 'notification_socket_listener.dart' show notificationRouterProvider;

/// Turns a Hermes run's need for a human into the same notification surface
/// chats and channels use.
///
/// Scope and honesty: this is a local listener. It fires while the app process
/// is alive — including backgrounded, where the router posts an OS notification
/// and a tap opens the approvals inbox. Hermes events that arrive while the app
/// is killed are not seen; that gap is what the deferred push stack closes.
///
/// The first scan only records what is already waiting, so launching the app
/// with an old approval does not alert about it. Later store changes alert for
/// each request once, keyed by origin + request id.
final hermesApprovalNotificationListenerProvider = Provider<void>((ref) {
  StreamSubscription<void>? subscription;
  final announced = <String>{};
  var primed = false;

  String keyOf(HermesPendingDesktopDecision decision) =>
      '${decision.origin}\u0000${decision.requestId}';

  AppNotification notificationFor(HermesPendingDesktopDecision decision) {
    final l10n = currentAppLocalizations();
    final title = switch (decision.kind) {
      HermesPendingDesktopDecisionKind.approval => l10n.hermesApprovalRequired,
      HermesPendingDesktopDecisionKind.clarification =>
        l10n.hermesClarificationTitle,
      HermesPendingDesktopDecisionKind.sudo => l10n.hermesSudoTitle,
      HermesPendingDesktopDecisionKind.secret => l10n.hermesSecretTitle,
      HermesPendingDesktopDecisionKind.mcpSetup => l10n.hermesMcpSetupTitle,
    };
    final prompt = decision.prompt?.trim();
    return AppNotification(
      kind: NotificationKind.hermesApproval,
      title: title,
      body: prompt == null || prompt.isEmpty
          ? l10n.hermesApprovalFallback
          : prompt,
      sourceId: decision.requestId,
      dedupKey: 'hermes-approval:${keyOf(decision)}',
    );
  }

  Future<void> scan() async {
    final config = ref.read(hermesConfigProvider);
    if (!config.enabled || config.mode != HermesBackendMode.desktopGateway) {
      return;
    }
    final records = await HermesPendingDecisionStore.all(
      connectionId: config.connectionId,
      origin: HermesConfig.connectionOrigin(config.baseUrl),
    );
    final present = {for (final record in records) keyOf(record)};
    if (!primed) {
      announced.addAll(present);
      primed = true;
      return;
    }
    for (final record in records) {
      final key = keyOf(record);
      if (!announced.add(key)) continue;
      if (!present.contains(key)) continue;
      await ref.read(notificationRouterProvider).route(notificationFor(record));
    }
  }

  void run() {
    unawaited(
      scan().catchError((Object error, StackTrace stackTrace) {
        DebugLogger.error(
          'hermes-approval-notification-scan-failed',
          scope: 'notifications/hermes',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  subscription = HermesPendingDecisionStore.changes.listen((_) => run());
  ref.onDispose(() => subscription?.cancel());
  run();
});
