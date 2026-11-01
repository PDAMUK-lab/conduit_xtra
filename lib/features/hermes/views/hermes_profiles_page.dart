import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_profile.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/navigation/routes.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Every Hermes profile on the server, with its model, state and skill count.
class HermesProfilesPage extends ConsumerWidget {
  const HermesProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final profilesAsync = ref.watch(hermesProfileListProvider);
    final active = ref.watch(hermesActiveProfileProvider).asData?.value;

    return UtilityPageScaffold.settings(
      title: l10n.hermesProfilesTitle,
      children: [
        Text(
          l10n.hermesProfilesSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        profilesAsync.when(
          data: (profiles) {
            if (profiles.isEmpty) {
              return _message(theme, l10n.hermesProfilesLoadFailed, theme.textSecondary);
            }
            return Column(
              children: [
                for (final profile in profiles) ...[
                  _ProfileTile(
                    key: ValueKey<String>('hermes-profile-${profile.name}'),
                    profile: profile,
                    isActive: active?.active == profile.name,
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
          error: (error, _) =>
              _message(theme, l10n.hermesProfilesLoadFailed, theme.error),
        ),
      ],
    );
  }

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

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({super.key, required this.profile, required this.isActive});

  final HermesProfileSummary profile;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final badges = <String>[
      if (profile.isDefault) l10n.hermesProfileDefault,
      if (isActive) l10n.hermesProfileActive,
      if (profile.gatewayRunning) l10n.hermesProfileGatewayRunning,
    ];
    return Container(
      decoration: BoxDecoration(
        color: theme.groupedSurface,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        onTap: () => context.push(Routes.hermesProfilePath(profile.name)),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.standard.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (profile.modelLabel.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        profile.modelLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmallStyle.copyWith(
                          color: theme.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: Spacing.xxs),
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.xxs,
                      children: [
                        for (final badge in badges)
                          Text(
                            badge,
                            style: AppTypography.captionStyle.copyWith(
                              color: theme.textSecondary,
                            ),
                          ),
                        Text(
                          l10n.hermesProfileSkills(profile.skillCount),
                          style: AppTypography.captionStyle.copyWith(
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
