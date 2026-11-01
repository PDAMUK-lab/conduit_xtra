import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_toolsets.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit_core/navigation/routes.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Every configurable toolset, with the switch that enables or disables it.
///
/// "Configured" is the server's own answer about whether the toolset's keys
/// are present; an enabled toolset without them fails at call time, so the row
/// says "Needs setup" rather than pretending it works.
class HermesToolsetsPage extends ConsumerStatefulWidget {
  const HermesToolsetsPage({super.key});

  @override
  ConsumerState<HermesToolsetsPage> createState() => _HermesToolsetsPageState();
}

class _HermesToolsetsPageState extends ConsumerState<HermesToolsetsPage> {
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final toolsetsAsync = ref.watch(hermesToolsetListProvider);

    return UtilityPageScaffold.settings(
      title: l10n.hermesToolsetsTitle,
      onRefresh: () async {
        ref.invalidate(hermesToolsetListProvider);
      },
      children: [
        Text(
          l10n.hermesToolsetsSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        toolsetsAsync.when(
          data: (toolsets) {
            if (toolsets.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Center(
                  child: Text(
                    l10n.hermesToolsetsLoadFailed,
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final toolset in toolsets) ...[
                  _toolsetRow(toolset, theme, l10n),
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
                l10n.hermesToolsetsLoadFailed,
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

  Widget _toolsetRow(
    HermesToolsetSummary toolset,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    final busy = _busy == toolset.name;
    return Container(
      key: ValueKey<String>('hermes-toolset-${toolset.name}'),
      decoration: BoxDecoration(
        color: theme.groupedSurface,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        onTap: () => context.push(Routes.hermesToolsetPath(toolset.name)),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
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
                            toolset.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.standard.copyWith(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!toolset.configured) ...[
                          const SizedBox(width: Spacing.sm),
                          Text(
                            l10n.hermesToolsetNeedsSetup,
                            style: AppTypography.captionStyle.copyWith(
                              color: theme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (toolset.description.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        toolset.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmallStyle.copyWith(
                          color: theme.textSecondary,
                        ),
                      ),
                    ],
                    if (toolset.tools.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${l10n.hermesToolsetTools}: ${toolset.tools.length}'
                        '${toolset.platformLabel.isEmpty ? '' : ' · ${toolset.platformLabel}'}',
                        style: AppTypography.captionStyle.copyWith(
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
              else
                AdaptiveSwitch(
                  value: toolset.enabled,
                  onChanged: (value) => _toggle(toolset, value),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(HermesToolsetSummary toolset, bool enabled) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _busy = toolset.name);
    try {
      await service.setToolsetEnabled(name: toolset.name, enabled: enabled);
      ref.invalidate(hermesToolsetListProvider);
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(
          context,
          _l10n(context).hermesToolsetToggleFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}
