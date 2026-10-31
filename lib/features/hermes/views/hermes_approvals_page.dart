import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_session.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit_core/features/hermes/services/hermes_pending_decision_store.dart';

import '../widgets/hermes_session_tile.dart' show openHermesSession;

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Every approval or question the agent is waiting on, across all of this
/// connection's conversations.
///
/// The inbox is a triage surface, not a second chat: approvals can be answered
/// here, and anything that needs a typed answer opens the conversation that
/// asked for it. A run that stops for approval while the phone is elsewhere is
/// the case this exists for.
class HermesApprovalsPage extends ConsumerWidget {
  const HermesApprovalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final pendingAsync = ref.watch(hermesPendingDecisionsProvider);
    final sessions = ref.watch(hermesSessionsProvider).asData?.value;

    return UtilityPageScaffold.settings(
      title: l10n.hermesApprovalsTitle,
      children: [
        Text(
          l10n.hermesApprovalsSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        pendingAsync.when(
          data: (pending) {
            if (pending.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Center(
                  child: Text(
                    l10n.hermesApprovalsEmpty,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final decision in pending) ...[
                  _ApprovalCard(
                    key: ValueKey<String>(decision.identity),
                    decision: decision,
                    sessionTitle: _sessionTitle(sessions, decision),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(
              child: Text(
                l10n.hermesApprovalsLoadFailed,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.error,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _sessionTitle(
    List<HermesSessionSummary>? sessions,
    HermesPendingDesktopDecision decision,
  ) {
    for (final session in sessions ?? const <HermesSessionSummary>[]) {
      if (session.id == decision.storedSessionId) return session.title;
    }
    return '';
  }
}

class _ApprovalCard extends ConsumerStatefulWidget {
  const _ApprovalCard({
    super.key,
    required this.decision,
    required this.sessionTitle,
  });

  final HermesPendingDesktopDecision decision;
  final String sessionTitle;

  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _resolving = false;
  bool _stopping = false;

  HermesPendingDesktopDecision get decision => widget.decision;

  bool get _isApproval =>
      decision.kind == HermesPendingDesktopDecisionKind.approval;

  /// The scope to allow with: the gateway's narrowest advertised choice,
  /// because approving from an inbox should never spend more permission than
  /// the run asked for.
  String get _allowChoice {
    final choices = decision.choices;
    if (choices.contains('once')) return 'once';
    for (final choice in choices) {
      if (choice != 'deny') return choice;
    }
    return 'once';
  }

  String get _title {
    final l10n = _l10n(context);
    return switch (decision.kind) {
      HermesPendingDesktopDecisionKind.approval => l10n.hermesApprovalRequired,
      HermesPendingDesktopDecisionKind.clarification =>
        l10n.hermesClarificationTitle,
      HermesPendingDesktopDecisionKind.sudo => l10n.hermesSudoTitle,
      HermesPendingDesktopDecisionKind.secret => l10n.hermesSecretTitle,
      HermesPendingDesktopDecisionKind.mcpSetup => l10n.hermesMcpSetupTitle,
    };
  }

  IconData get _icon => switch (decision.kind) {
    HermesPendingDesktopDecisionKind.approval => Icons.verified_user_outlined,
    HermesPendingDesktopDecisionKind.clarification => Icons.help_outline,
    HermesPendingDesktopDecisionKind.sudo => Icons.admin_panel_settings_outlined,
    HermesPendingDesktopDecisionKind.secret => Icons.key_outlined,
    HermesPendingDesktopDecisionKind.mcpSetup => Icons.extension_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final prompt = decision.prompt?.trim() ?? '';
    final session = widget.sessionTitle.trim();
    final expiry = _relativeExpiry(context);

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: theme.groupedSurface,
        borderRadius: BorderRadius.circular(
          context.usesCupertinoChrome ? AppBorderRadius.md : AppBorderRadius.card,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, size: 18, color: theme.buttonPrimary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  _title,
                  style: AppTypography.standard.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_resolving)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                ConduitIconButton(
                  key: ValueKey<String>(
                    'hermes-approval-stop-${decision.requestId}',
                  ),
                  icon: Icons.stop_circle_outlined,
                  iconColor: theme.error,
                  tooltip: l10n.stopGenerating,
                  isCompact: true,
                  onPressed: _stopping ? null : _stopRun,
                ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            prompt.isEmpty ? l10n.hermesApprovalFallback : prompt,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmallStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                session.isEmpty ? l10n.hermesSessionUntitled : session,
                style: AppTypography.captionStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
              if (expiry != null)
                Text(
                  expiry,
                  style: AppTypography.captionStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              if (_isApproval) ...[
                ConduitButton(
                  key: ValueKey<String>(
                    'hermes-approval-allow-${decision.requestId}',
                  ),
                  text: switch (_allowChoice) {
                    'session' => l10n.hermesApprovalAllowSession,
                    'always' => l10n.hermesApprovalAlwaysAllow,
                    _ => l10n.hermesApprovalAllowOnce,
                  },
                  isCompact: true,
                  isLoading: _resolving,
                  onPressed: _resolving ? null : () => _resolve(_allowChoice),
                ),
                const SizedBox(width: Spacing.sm),
                ConduitButton(
                  key: ValueKey<String>(
                    'hermes-approval-deny-${decision.requestId}',
                  ),
                  text: l10n.hermesApprovalDenyAction,
                  isSecondary: true,
                  isCompact: true,
                  onPressed: _resolving ? null : () => _resolve('deny'),
                ),
              ],
              const Spacer(),
              ConduitButton(
                key: ValueKey<String>(
                  'hermes-approval-open-${decision.requestId}',
                ),
                text: l10n.hermesApprovalsOpenConversation,
                isSecondary: true,
                isCompact: true,
                onPressed: _resolving ? null : _openConversation,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _relativeExpiry(BuildContext context) {
    final remaining = decision.expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return null;
    final hours = remaining.inHours;
    if (hours >= 1) return _l10n(context).hermesApprovalsExpiresInHours(hours);
    final minutes = remaining.inMinutes.clamp(1, 59);
    return _l10n(context).hermesApprovalsExpiresInMinutes(minutes);
  }

  Future<void> _resolve(String choice) async {
    final service = ref.read(hermesApiServiceProvider);
    // Only the desktop gateway carries session-scoped approvals; the
    // responses-API backend has no session to scope one to.
    if (service is! HermesDesktopApiService) return;
    setState(() => _resolving = true);
    try {
      await service.resolveApprovalChoiceForSession(
        decision.storedSessionId,
        approvalId: decision.requestId,
        choice: choice,
      );
      await HermesPendingDecisionStore.resolve(
        origin: decision.origin,
        runtimeId: decision.runtimeId,
        requestId: decision.requestId,
        connectionId: decision.connectionId,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _resolving = false);
        UiUtils.showMessage(
          context,
          _l10n(context).hermesApprovalResolveFailed,
          isError: true,
        );
      }
    }
  }

  Future<void> _stopRun() async {
    final l10n = _l10n(context);
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: l10n.stopGenerating,
      message: l10n.hermesApprovalsStopConfirm,
      confirmText: l10n.stopGenerating,
      cancelText: l10n.cancel,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _stopping = true);
    try {
      await service.interrupt(decision.storedSessionId);
      if (!mounted) return;
      UiUtils.showMessage(context, l10n.hermesApprovalsStopped);
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(context, l10n.chatStopResponseFailed, isError: true);
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  Future<void> _openConversation() async {
    final session = HermesSessionSummary(
      id: decision.storedSessionId,
      title: widget.sessionTitle,
    );
    await openHermesSession(context, ref, session);
  }
}
