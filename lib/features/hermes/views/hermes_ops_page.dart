import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_fs.dart';
import 'package:conduit_core/features/hermes/models/hermes_ops.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

String _bytes(int value) {
  if (value >= 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '$value B';
}

/// Maintenance actions on the server: doctor, security audit and backup run as
/// background actions and are polled until they exit; checkpoints can be
/// inventoried and pruned; hooks are listed with whether they are approved.
///
/// Restore is not here because the dashboard exposes no restore route — that
/// stays a terminal job (`hermes checkpoints`).
class HermesOpsPage extends ConsumerStatefulWidget {
  const HermesOpsPage({super.key});

  @override
  ConsumerState<HermesOpsPage> createState() => _HermesOpsPageState();
}

class _HermesOpsPageState extends ConsumerState<HermesOpsPage> {
  Timer? _poll;
  String? _action;
  HermesActionStatus? _status;
  String? _error;
  bool _starting = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final checkpointsAsync = ref.watch(hermesCheckpointsProvider);
    final hooksAsync = ref.watch(hermesHooksProvider);

    return UtilityPageScaffold.settings(
      title: l10n.hermesOpsTitle,
      children: [
        Text(
          l10n.hermesOpsSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Row(
          children: [
            Expanded(
              child: ConduitButton(
                key: const ValueKey<String>('hermes-ops-doctor'),
                text: l10n.hermesOpsDoctor,
                isSecondary: true,
                isCompact: true,
                onPressed: _busy ? null : () => _start('doctor'),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: ConduitButton(
                key: const ValueKey<String>('hermes-ops-audit'),
                text: l10n.hermesOpsSecurityAudit,
                isSecondary: true,
                isCompact: true,
                onPressed: _busy ? null : () => _start('security-audit'),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: ConduitButton(
                key: const ValueKey<String>('hermes-ops-backup'),
                text: l10n.hermesOpsBackup,
                isSecondary: true,
                isCompact: true,
                onPressed: _busy ? null : () => _start('backup'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        if (_action != null) _actionCard(theme, l10n),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              _error!,
              style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
            ),
          ),
        const SizedBox(height: Spacing.lg),
        _sectionTitle(l10n.hermesOpsCheckpoints, theme),
        checkpointsAsync.when(
          data: (checkpoints) {
            if (checkpoints == null || checkpoints.isEmpty) {
              return _card(
                theme,
                Text(
                  l10n.hermesOpsCheckpointsEmpty,
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              );
            }
            return Column(
              children: [
                _card(
                  theme,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${checkpoints.sessions.length} · ${_bytes(checkpoints.totalBytes)}',
                        style: AppTypography.standard.copyWith(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      for (final session in checkpoints.sessions.take(8)) ...[
                        const SizedBox(height: Spacing.xxs),
                        Text(
                          '${session.session} · ${session.files} · ${_bytes(session.bytes)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.captionStyle.copyWith(
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                ConduitButton(
                  key: const ValueKey<String>('hermes-ops-prune'),
                  text: l10n.hermesOpsPrune,
                  isSecondary: true,
                  isFullWidth: true,
                  onPressed: _busy ? null : _prune,
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesOpsFailed, theme.error),
        ),
        const SizedBox(height: Spacing.lg),
        _sectionTitle(l10n.hermesOpsHooks, theme),
        hooksAsync.when(
          data: (hooks) {
            if (hooks.isEmpty) {
              return _card(
                theme,
                Text(
                  l10n.hermesOpsHooksEmpty,
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final hook in hooks) ...[
                  _card(
                    theme,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${hook.event} · ${hook.command}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.codeStyle.copyWith(
                            color: theme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: Spacing.xxs),
                        Text(
                          hook.allowed
                              ? l10n.hermesOpsHookAllowed
                              : l10n.hermesOpsHookBlocked,
                          style: AppTypography.captionStyle.copyWith(
                            color: hook.allowed ? theme.textSecondary : theme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesOpsFailed, theme.error),
        ),
        const SizedBox(height: Spacing.lg),
        _sectionTitle(l10n.hermesBackupsSection, theme),
        const SizedBox(height: Spacing.xxs),
        Text(
          l10n.hermesRestoreCliOnly,
          style: AppTypography.captionStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        _backupsSection(theme, l10n),
      ],
    );
  }

  /// Backups the server wrote (`<profile home>/backups`), listed through the
  /// files API because there is no listing route for them. Restoring is not
  /// offered: the server refuses an import while the gateway owns the profile,
  /// so it stays a terminal job and the page says so.
  Widget _backupsSection(ConduitThemeExtension theme, AppLocalizations l10n) {
    final configPath = ref.watch(hermesRawConfigProvider).asData?.value?.path;
    if (configPath == null) return const SizedBox.shrink();
    final dir =
        '${configPath.substring(0, configPath.lastIndexOf('/'))}/backups';
    final listing = ref.watch(hermesFsListingProvider(dir)).asData?.value;
    final archives =
        (listing?.entries ?? const <HermesFsEntry>[])
            .where((e) => !e.isDirectory && e.name.endsWith('.zip'))
            .toList()
          ..sort((a, b) => b.name.compareTo(a.name));
    if (archives.isEmpty) {
      return _card(
        theme,
        Text(
          l10n.hermesRestoreEmpty,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final archive in archives.take(6)) ...[
          Container(
            key: ValueKey<String>('hermes-backup-${archive.path}'),
            decoration: BoxDecoration(
              color: theme.groupedSurface,
              borderRadius: BorderRadius.circular(AppBorderRadius.card),
            ),
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.archive_outlined,
                  size: IconSize.listItem,
                  color: theme.iconSecondary,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    archive.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.codeStyle.copyWith(
                      color: theme.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xs),
        ],
      ],
    );
  }

  bool get _busy => _starting || (_status?.running ?? false);

  Widget _actionCard(ConduitThemeExtension theme, AppLocalizations l10n) {
    final status = _status;
    final tail = status == null
        ? const <String>[]
        : status.lines.length > 30
        ? status.lines.sublist(status.lines.length - 30)
        : status.lines;
    return _card(
      theme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_action ?? ''} · ${status?.running == true ? l10n.hermesOpsRunning : '${l10n.hermesOpsExit}: ${status?.exitCode ?? '—'}'}',
                  style: AppTypography.standard.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_starting || status?.running == true)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (status == null && _error != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              _error!,
              style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
            ),
          ],
          if (tail.isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            SelectableText(
              tail.join('\n'),
              style: AppTypography.codeStyle.copyWith(
                color: theme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, ConduitThemeExtension theme) => Padding(
    padding: const EdgeInsets.only(bottom: Spacing.xs),
    child: Text(
      text,
      style: AppTypography.labelStyle.copyWith(
        color: theme.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _card(ConduitThemeExtension theme, Widget child) => Container(
    padding: const EdgeInsets.all(Spacing.md),
    decoration: BoxDecoration(
      color: theme.groupedSurface,
      borderRadius: BorderRadius.circular(AppBorderRadius.card),
    ),
    child: child,
  );

  Widget _message(ConduitThemeExtension theme, String text, Color color) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmallStyle.copyWith(color: color),
          ),
        ),
      );

  Future<void> _start(String action) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() {
      _action = action;
      _status = null;
      _error = null;
      _starting = true;
    });
    try {
      final status = switch (action) {
        'doctor' => await service.spawnDoctor(),
        'security-audit' => await service.spawnSecurityAudit(),
        'backup' => await service.spawnBackup(),
        _ => null,
      };
      if (!mounted) return;
      setState(() {
        _starting = false;
        _status = status;
      });
      _pollUntilDone(action);
    } catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = _errorText(error);
        });
        UiUtils.showMessage(context, _errorText(error), isError: true);
      }
    }
  }

  Future<void> _prune() async {
    final l10n = _l10n(context);
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: l10n.hermesOpsPrune,
      message: l10n.hermesOpsPruneConfirm,
      confirmText: l10n.hermesOpsPrune,
      cancelText: l10n.cancel,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() {
      _action = 'checkpoints-prune';
      _status = null;
      _error = null;
      _starting = true;
    });
    try {
      final status = await service.pruneCheckpoints();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _status = status;
      });
      ref.invalidate(hermesCheckpointsProvider);
      _pollUntilDone('checkpoints-prune');
    } catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = _errorText(error);
        });
        UiUtils.showMessage(context, _errorText(error), isError: true);
      }
    }
  }

  /// The server's own reason when it gives one (a 500 carries the spawn error
  /// in `detail`), so a failed action names its cause instead of "failed".
  String _errorText(Object error) {
    final match = RegExp(
      r'"detail"\s*:\s*"([^"]{1,300})"',
    ).firstMatch(error.toString());
    return match?.group(1) ?? _l10n(context).hermesOpsFailed;
  }

  void _pollUntilDone(String action) {
    _poll?.cancel();
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    _poll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = await service.actionStatus(action);
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _status = status);
        if (status == null || !status.running) {
          timer.cancel();
          if (action == 'checkpoints-prune') {
            ref.invalidate(hermesCheckpointsProvider);
          }
        }
      } catch (_) {
        timer.cancel();
      }
    });
  }
}
