import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_local_models.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

String _gb(int bytes) => '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

/// The node's local engine, read-only.
///
/// Deliberately does not start or stop a server: on this fleet the serving
/// worker is often started outside this manager, so a "start" here would spawn
/// a second server and a "stop" could kill one this manager does not own.
class HermesLocalModelsPage extends ConsumerStatefulWidget {
  const HermesLocalModelsPage({super.key});

  @override
  ConsumerState<HermesLocalModelsPage> createState() =>
      _HermesLocalModelsPageState();
}

class _HermesLocalModelsPageState extends ConsumerState<HermesLocalModelsPage> {
  String? _busyPeer;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final status = ref.watch(hermesLocalModelStatusProvider);
    final hardware = ref.watch(hermesLocalModelHardwareProvider);

    return UtilityPageScaffold.settings(
      title: l10n.hermesLocalModelsTitle,
      onRefresh: () async {
        ref.invalidate(hermesLocalModelStatusProvider);
        ref.invalidate(hermesLocalModelHardwareProvider);
      },
      children: [
        Text(
          l10n.hermesLocalModelsSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        status.when(
          data: (value) {
            if (value == null) {
              return _card(
                theme,
                Text(
                  l10n.hermesLocalLoadFailed,
                  style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _card(
                  theme,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(
                        l10n.hermesLocalManager,
                        value.enabled
                            ? l10n.hermesLocalEnabled
                            : l10n.hermesLocalDisabled,
                        theme,
                        good: value.enabled,
                      ),
                      _row(
                        l10n.hermesLocalRuntime,
                        [
                          value.runtimeInstalled
                              ? l10n.hermesLocalInstalled
                              : l10n.hermesLocalNotInstalled,
                          if (value.runtimeBackend != null &&
                              value.runtimeBackend!.isNotEmpty)
                            value.runtimeBackend!,
                          if (value.tag.isNotEmpty) value.tag,
                          if (value.updateAvailable)
                            l10n.hermesLocalUpdateAvailable,
                        ].join(' · '),
                        theme,
                        good: value.runtimeInstalled,
                      ),
                      _row(
                        l10n.hermesLocalServer,
                        value.serverRunning
                            ? (value.serverBaseUrl ?? l10n.hermesLocalRunning)
                            : l10n.hermesLocalStopped,
                        theme,
                        good: value.serverRunning,
                      ),
                      if (value.activeModelId != null &&
                          value.activeModelId!.isNotEmpty)
                        _row(
                          l10n.hermesLocalActiveModel,
                          value.activeModelId!,
                          theme,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                if (value.servedElsewhere)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: Text(
                      l10n.hermesLocalServedElsewhere(
                        value.externalServer!.baseUrl,
                        value.externalServer!.model ?? '—',
                      ),
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textPrimary,
                      ),
                    ),
                  ),
                if (!value.enabled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: Text(
                      l10n.hermesLocalOutsideNote,
                      style: AppTypography.captionStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ),
                if (value.peers.isNotEmpty) ...[
                  _card(
                    theme,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.hermesLocalFleet,
                          style: AppTypography.standard.copyWith(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Spacing.xxs),
                        for (final peer in value.peers)
                          _peerRow(peer, theme, l10n),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
                _card(
                  theme,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l10n.hermesLocalModelsCount} · ${value.modelCount}',
                        style: AppTypography.standard.copyWith(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      if (value.models.isEmpty)
                        Text(
                          l10n.hermesLocalNoModels,
                          style: AppTypography.captionStyle.copyWith(
                            color: theme.textSecondary,
                          ),
                        )
                      else
                        for (final model in value.models.take(8))
                          Padding(
                            padding: const EdgeInsets.only(top: Spacing.xxs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    model.name.isEmpty ? model.id : model.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.codeStyle.copyWith(
                                      color: theme.textPrimary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  _gb(model.sizeBytes),
                                  style: AppTypography.captionStyle.copyWith(
                                    color: theme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      if (value.modelsDir.isNotEmpty) ...[
                        const SizedBox(height: Spacing.xs),
                        Text(
                          value.modelsDir,
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
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _card(
            theme,
            Text(
              l10n.hermesLocalLoadFailed,
              style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          l10n.hermesLocalHardwareTitle,
          style: AppTypography.labelStyle.copyWith(
            color: theme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        hardware.when(
          data: (value) {
            if (value == null) return const SizedBox.shrink();
            final used = value.vramUsedBytes;
            return _card(
              theme,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(
                    l10n.hermesLocalGpu,
                    value.gpuName ?? (value.uma ? l10n.hermesLocalUma : '—'),
                    theme,
                  ),
                  _row(
                    l10n.hermesLocalVram,
                    used == null
                        ? '${_gb(value.vramTotalBytes)} · ${_gb(value.vramUsableBytes)} ${l10n.hermesLocalUsable}'
                        : '${_gb(used)} / ${_gb(value.vramTotalBytes)}',
                    theme,
                  ),
                  _row(
                    l10n.hermesLocalRam,
                    '${_gb(value.ramAvailableBytes)} / ${_gb(value.ramTotalBytes)}',
                    theme,
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (error, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _peerRow(
    HermesLocalPeer peer,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    final action = peer.up ? 'release' : 'raise';
    final allowed = peer.up ? peer.canRelease : peer.canRaise;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: Row(
        children: [
          Icon(
            peer.up ? Icons.circle : Icons.circle_outlined,
            size: 8,
            color: peer.up ? theme.success : theme.textSecondary,
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.codeStyle.copyWith(
                    color: theme.textPrimary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  peer.up
                      ? l10n.hermesLocalPeerServing(peer.model ?? peer.baseUrl)
                      : l10n.hermesLocalPeerDown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.captionStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (allowed)
            _busyPeer == peer.name
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ConduitButton(
                    key: ValueKey<String>('hermes-peer-$action-${peer.name}'),
                    text: peer.up
                        ? l10n.hermesLocalRelease
                        : l10n.hermesLocalRaise,
                    isCompact: true,
                    isSecondary: true,
                    onPressed: () => _peerAction(peer, action, l10n),
                  ),
        ],
      ),
    );
  }

  Future<void> _peerAction(
    HermesLocalPeer peer,
    String action,
    AppLocalizations l10n,
  ) async {
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: action == 'raise' ? l10n.hermesLocalRaise : l10n.hermesLocalRelease,
      message: l10n.hermesLocalPeerActionConfirm(peer.name, action),
      confirmText: action == 'raise' ? l10n.hermesLocalRaise : l10n.hermesLocalRelease,
      cancelText: l10n.cancel,
    );
    if (!confirmed || !mounted) return;
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _busyPeer = peer.name);
    try {
      final result = await service.peerAction(peer.name, action);
      ref.invalidate(hermesLocalModelStatusProvider);
      if (!mounted) return;
      UiUtils.showMessage(
        context,
        result?.ok == true
            ? (result!.message.isEmpty ? l10n.hermesLocalPeerActionOk : result.message)
            : (result?.message.isNotEmpty == true
                  ? result!.message
                  : l10n.hermesLocalPeerActionFailed),
        isError: result?.ok != true,
      );
    } catch (error) {
      if (!mounted) return;
      final detail = RegExp(r'"detail"\s*:\s*"([^"]{1,300})"')
          .firstMatch(error.toString())
          ?.group(1);
      UiUtils.showMessage(
        context,
        detail ?? l10n.hermesLocalPeerActionFailed,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyPeer = null);
    }
  }

  Widget _card(ConduitThemeExtension theme, Widget child) => Container(
    padding: const EdgeInsets.all(Spacing.md),
    decoration: BoxDecoration(
      color: theme.groupedSurface,
      borderRadius: BorderRadius.circular(AppBorderRadius.card),
    ),
    child: child,
  );

  Widget _row(
    String label,
    String value,
    ConduitThemeExtension theme, {
    bool? good,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySmallStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 2,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.codeStyle.copyWith(
              color: good == null
                  ? theme.textPrimary
                  : (good ? theme.success : theme.textSecondary),
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}
