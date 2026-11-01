import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_git.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/navigation/routes.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Read-only view of the agent's repository: branch, ahead/behind, the changed
/// files and each file's diff. Stage, commit and push are not wired — they can
/// rewrite history and belong behind their own confirmation.
class HermesGitPage extends ConsumerWidget {
  const HermesGitPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final defaultsAsync = ref.watch(hermesFsDefaultsProvider);
    final path = defaultsAsync.asData?.value?.cwd;

    return UtilityPageScaffold.settings(
      title: l10n.hermesGitTitle,
      children: [
        Text(
          l10n.hermesGitSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        if (path == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ref
              .watch(hermesGitStatusProvider(path))
              .when(
                data: (status) {
                  if (status == null) {
                    return _message(
                      theme,
                      l10n.hermesGitNotRepo,
                      theme.textSecondary,
                    );
                  }
                  return _status(context, status, path, theme, l10n);
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: Spacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) =>
                    _message(theme, l10n.hermesGitLoadFailed, theme.error),
              ),
      ],
    );
  }

  Widget _status(
    BuildContext context,
    HermesGitStatus status,
    String path,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    final branch = status.branch ?? (status.detached ? 'detached' : '—');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: theme.groupedSurface,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                branch,
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
                  l10n.hermesGitChanged(status.changed),
                  if (status.ahead > 0 || status.behind > 0)
                    l10n.hermesGitAheadBehind(status.ahead, status.behind),
                  '+${status.added} −${status.removed}',
                ].join(' · '),
                style: AppTypography.captionStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (status.clean)
          _message(theme, l10n.hermesGitClean, theme.textSecondary)
        else
          for (final file in status.files) ...[
            Container(
              key: ValueKey<String>('hermes-git-file-${file.path}'),
              decoration: BoxDecoration(
                color: theme.groupedSurface,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
                onTap: () => context.push(
                  Routes.hermesGitDiffPath(path, file.path),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        child: Text(
                          file.marker,
                          style: AppTypography.codeStyle.copyWith(
                            color: file.conflicted ? theme.error : theme.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          file.path,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.codeStyle.copyWith(
                            color: theme.textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: IconSize.listItem,
                        color: theme.iconSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
          ],
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
