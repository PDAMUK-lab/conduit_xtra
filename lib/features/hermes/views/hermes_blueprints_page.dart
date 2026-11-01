import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_blueprint.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';

import '../widgets/hermes_blueprint_form.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Ready-made automations: pick one, fill its slots, get a scheduled job.
class HermesBlueprintsPage extends ConsumerWidget {
  const HermesBlueprintsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final blueprints = ref.watch(hermesBlueprintsProvider);

    return UtilityPageScaffold.settings(
      title: l10n.hermesBlueprintsTitle,
      onRefresh: () async {
        ref.invalidate(hermesBlueprintsProvider);
      },
      children: [
        Text(
          l10n.hermesBlueprintsSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        blueprints.when(
          data: (entries) {
            if (entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Center(
                  child: Text(
                    l10n.hermesBlueprintEmpty,
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                ),
              );
            }
            final byCategory = <String, List<HermesBlueprint>>{};
            for (final entry in entries) {
              byCategory.putIfAbsent(entry.category, () => []).add(entry);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in byCategory.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.xs),
                    child: Text(
                      group.key.isEmpty
                          ? l10n.hermesBlueprintsOther
                          : '${group.key[0].toUpperCase()}${group.key.substring(1)}',
                      style: AppTypography.labelStyle.copyWith(
                        color: theme.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final blueprint in group.value) ...[
                    _BlueprintCard(blueprint: blueprint),
                    const SizedBox(height: Spacing.xs),
                  ],
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
                l10n.hermesBlueprintLoadFailed,
                style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BlueprintCard extends ConsumerWidget {
  const _BlueprintCard({required this.blueprint});

  final HermesBlueprint blueprint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.conduitTheme;
    final l10n = _l10n(context);
    return Container(
      key: ValueKey<String>('hermes-blueprint-${blueprint.key}'),
      decoration: BoxDecoration(
        color: theme.groupedSurface,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        onTap: () async {
          final created = await showHermesBlueprintForm(context, blueprint);
          if (created == true && context.mounted) {
            ref.invalidate(hermesJobsProvider);
            UiUtils.showMessage(context, l10n.hermesBlueprintCreated);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      blueprint.title,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (blueprint.isPlugin)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.xs,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.surfaceBackground,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l10n.hermesBlueprintPlugin,
                        style: AppTypography.captionStyle.copyWith(
                          color: theme.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                blueprint.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
              if (blueprint.scheduleHuman.isNotEmpty) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  blueprint.scheduleHuman,
                  style: AppTypography.captionStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
