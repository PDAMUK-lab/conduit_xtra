import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_memory.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Which memory provider the agent uses, what is ready, and what a reset would
/// erase. Switching is a `PUT /api/memory/provider`; the server refuses a
/// provider that is not ready, so only ready rows offer the action.
class HermesMemoryPage extends ConsumerStatefulWidget {
  const HermesMemoryPage({super.key});

  @override
  ConsumerState<HermesMemoryPage> createState() => _HermesMemoryPageState();
}

class _HermesMemoryPageState extends ConsumerState<HermesMemoryPage> {
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final statusAsync = ref.watch(hermesMemoryStatusProvider);

    return UtilityPageScaffold.settings(
      title: l10n.hermesWikiSettings,
      children: [
        Text(
          l10n.hermesMemorySubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        statusAsync.when(
          data: (status) {
            if (status == null) {
              return _message(theme, l10n.hermesMemoryLoadFailed, theme.error);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _activeCard(status, theme, l10n),
                const SizedBox(height: Spacing.lg),
                _sectionTitle(l10n.hermesMemoryProviders, theme),
                const SizedBox(height: Spacing.xs),
                for (final provider in status.providers) ...[
                  _providerCard(provider, status, theme, l10n),
                  const SizedBox(height: Spacing.sm),
                ],
                if (status.hasBuiltinFiles) ...[
                  const SizedBox(height: Spacing.lg),
                  _sectionTitle(l10n.hermesMemoryFiles, theme),
                  const SizedBox(height: Spacing.xs),
                  _fileRow('MEMORY.md', status.memoryFileBytes, theme),
                  const SizedBox(height: Spacing.xxs),
                  _fileRow('USER.md', status.userFileBytes, theme),
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesMemoryLoadFailed, theme.error),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text, ConduitThemeExtension theme) => Text(
    text,
    style: AppTypography.labelStyle.copyWith(
      color: theme.textSecondary,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _message(ConduitThemeExtension theme, String text, Color color) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmallStyle.copyWith(color: color),
          ),
        ),
      );

  Widget _activeCard(
    HermesMemoryStatus status,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) => Container(
    padding: const EdgeInsets.all(Spacing.md),
    decoration: BoxDecoration(
      color: theme.groupedSurface,
      borderRadius: BorderRadius.circular(AppBorderRadius.card),
    ),
    child: Row(
      children: [
        Icon(Icons.memory_outlined, size: 18, color: theme.buttonPrimary),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.hermesMemoryActive,
                style: AppTypography.labelStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                status.active.isEmpty ? l10n.hermesMemoryNone : status.active,
                style: AppTypography.standard.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _providerCard(
    HermesMemoryProvider provider,
    HermesMemoryStatus status,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    final isActive = provider.name == status.active;
    final busy = _busy == provider.name;
    return Container(
      key: ValueKey<String>('hermes-memory-provider-${provider.name}'),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: theme.groupedSurface,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        provider.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.standard.copyWith(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Text(
                      provider.ready
                          ? l10n.hermesMemoryReady
                          : (provider.status.isEmpty
                                ? l10n.hermesMemoryUnavailable
                                : provider.status),
                      style: AppTypography.captionStyle.copyWith(
                        color: provider.ready
                            ? theme.textSecondary
                            : theme.error,
                      ),
                    ),
                  ],
                ),
                if (provider.description.isNotEmpty) ...[
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    provider.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(Spacing.sm),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (!isActive && provider.ready)
            ConduitButton(
              key: ValueKey<String>('hermes-memory-use-${provider.name}'),
              text: l10n.hermesMemoryUse,
              isSecondary: true,
              isCompact: true,
              onPressed: _busy == null ? () => _use(provider.name) : null,
            ),
        ],
      ),
    );
  }

  Widget _fileRow(String name, int bytes, ConduitThemeExtension theme) =>
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.groupedSurface,
          borderRadius: BorderRadius.circular(AppBorderRadius.card),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: AppTypography.standard.copyWith(color: theme.textPrimary),
              ),
            ),
            Text(
              _formatBytes(bytes),
              style: AppTypography.bodySmallStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ],
        ),
      );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _use(String provider) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _busy = provider);
    try {
      await service.setMemoryProvider(provider);
      ref.invalidate(hermesMemoryStatusProvider);
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(
          context,
          _l10n(context).hermesMemorySwitchFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}
