import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_git.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/navigation/routes.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Read-only view of a repository: branch, ahead/behind, changed files and each
/// file's diff. The path starts at the enclosing repository of the agent's
/// working directory; when that directory is not a repository the page offers
/// the repositories directly inside it, and the path stays editable.
class HermesGitPage extends ConsumerStatefulWidget {
  const HermesGitPage({super.key});

  @override
  ConsumerState<HermesGitPage> createState() => _HermesGitPageState();
}

class _HermesGitPageState extends ConsumerState<HermesGitPage> {
  final _controller = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final cwd = ref.watch(hermesFsDefaultsProvider).asData?.value?.cwd;
    final chosen = ref.watch(hermesGitPathProvider);
    final root = cwd == null
        ? null
        : ref.watch(hermesGitRootProvider(cwd)).asData?.value;
    final path = chosen ?? root;

    if (!_seeded && path != null) {
      _seeded = true;
      _controller.text = path;
    }

    return UtilityPageScaffold.settings(
      title: l10n.hermesGitTitle,
      children: [
        Text(
          l10n.hermesGitSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey<String>('hermes-git-path'),
                controller: _controller,
                style: AppTypography.codeStyle.copyWith(
                  color: theme.textPrimary,
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  hintText: l10n.hermesGitPathHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.go,
                onSubmitted: _openPath,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            ConduitButton(
              key: const ValueKey<String>('hermes-git-open'),
              text: l10n.hermesGitOpen,
              isCompact: true,
              onPressed: () => _openPath(_controller.text),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        if (cwd == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (path != null)
          _statusSection(path, theme, l10n)
        else
          _discoverSection(cwd, theme, l10n),
      ],
    );
  }

  Widget _statusSection(
    String path,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    return ref
        .watch(hermesGitStatusProvider(path))
        .when(
          data: (status) {
            if (status == null) {
              return _message(theme, l10n.hermesGitNotRepo, theme.textSecondary);
            }
            return _status(context, status, path, theme, l10n);
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesGitLoadFailed, theme.error),
        );
  }

  /// The default path is not a repository: offer the ones beside it.
  Widget _discoverSection(
    String cwd,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    return ref
        .watch(hermesGitReposProvider(cwd))
        .when(
          data: (roots) {
            if (roots.isEmpty) {
              return _message(theme, l10n.hermesGitNotRepo, theme.textSecondary);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.hermesGitChooseRepo,
                  style: AppTypography.captionStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                for (final root in roots) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: theme.groupedSurface,
                      borderRadius: BorderRadius.circular(AppBorderRadius.card),
                    ),
                    child: InkWell(
                      key: ValueKey<String>('hermes-git-repo-$root'),
                      borderRadius: BorderRadius.circular(AppBorderRadius.card),
                      onTap: () => _select(root),
                      child: Padding(
                        padding: const EdgeInsets.all(Spacing.md),
                        child: Text(
                          root,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.codeStyle.copyWith(
                            color: theme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesGitLoadFailed, theme.error),
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
                onTap: () =>
                    context.push(Routes.hermesGitDiffPath(path, file.path)),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        child: Text(
                          file.marker,
                          style: AppTypography.codeStyle.copyWith(
                            color: file.conflicted
                                ? theme.error
                                : theme.textSecondary,
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

  void _openPath(String value) {
    final path = value.trim();
    if (path.isEmpty) return;
    _select(path);
  }

  void _select(String path) {
    _controller.text = path;
    ref.read(hermesGitPathProvider.notifier).select(path);
  }
}
