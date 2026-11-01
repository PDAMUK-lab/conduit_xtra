import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

String _tokens(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

String _cost(double value) => value <= 0 ? '—' : '\$${value.toStringAsFixed(2)}';

/// Read-only usage: tokens, sessions, cost and the tools that ran, for the
/// last 7/30/90 days from the dashboard's session history.
class HermesAnalyticsPage extends ConsumerStatefulWidget {
  const HermesAnalyticsPage({super.key});

  @override
  ConsumerState<HermesAnalyticsPage> createState() =>
      _HermesAnalyticsPageState();
}

class _HermesAnalyticsPageState extends ConsumerState<HermesAnalyticsPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final usageAsync = ref.watch(hermesUsageAnalyticsProvider(_days));

    return UtilityPageScaffold.settings(
      title: l10n.hermesAnalyticsTitle,
      onRefresh: () async {
        ref.invalidate(hermesUsageAnalyticsProvider);
      },
      children: [
        Text(
          l10n.hermesAnalyticsSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          children: [
            for (final days in const [7, 30, 90])
              ChoiceChip(
                key: ValueKey<String>('hermes-analytics-days-$days'),
                label: Text('${days}d'),
                selected: _days == days,
                onSelected: (_) => setState(() => _days = days),
              ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        usageAsync.when(
          data: (usage) {
            if (usage == null) {
              return _message(theme, l10n.hermesAnalyticsLoadFailed, theme.error);
            }
            final totals = usage.totals;
            if (totals.totalTokens == 0 && totals.sessions == 0) {
              return _message(
                theme,
                l10n.hermesAnalyticsNoUsage,
                theme.textSecondary,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _card(
                  theme,
                  Row(
                    children: [
                      _metric(
                        theme,
                        l10n.hermesAnalyticsTokens,
                        _tokens(totals.totalTokens),
                      ),
                      _metric(
                        theme,
                        l10n.hermesAnalyticsSessions,
                        '${totals.sessions}',
                      ),
                      _metric(
                        theme,
                        l10n.hermesAnalyticsCost,
                        _cost(
                          totals.actualCost > 0
                              ? totals.actualCost
                              : totals.estimatedCost,
                        ),
                      ),
                    ],
                  ),
                ),
                if (usage.byModel.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  _sectionTitle(l10n.hermesAnalyticsByModel, theme),
                  for (final model in usage.byModel.take(20)) ...[
                    _card(
                      theme,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model.model,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.standard.copyWith(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: Spacing.xxs),
                          Text(
                            [
                              _tokens(model.totals.totalTokens),
                              '${model.totals.sessions}',
                              _cost(model.totals.actualCost > 0
                                  ? model.totals.actualCost
                                  : model.totals.estimatedCost),
                            ].join(' · '),
                            style: AppTypography.captionStyle.copyWith(
                              color: theme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                  ],
                ],
                if (usage.tools.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  _sectionTitle(l10n.hermesAnalyticsTools, theme),
                  _card(
                    theme,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry
                            in (usage.tools.entries.toList()
                                  ..sort((a, b) => b.value.compareTo(a.value)))
                                .take(10))
                          Padding(
                            padding: const EdgeInsets.only(bottom: Spacing.xxs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodySmallStyle.copyWith(
                                      color: theme.textPrimary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${entry.value}',
                                  style: AppTypography.captionStyle.copyWith(
                                    color: theme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesAnalyticsLoadFailed, theme.error),
        ),
      ],
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

  Widget _metric(ConduitThemeExtension theme, String label, String value) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: AppTypography.titleMediumStyle.copyWith(
                color: theme.textPrimary,
              ),
            ),
            Text(
              label,
              style: AppTypography.captionStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ],
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
        padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmallStyle.copyWith(color: color),
          ),
        ),
      );
}
