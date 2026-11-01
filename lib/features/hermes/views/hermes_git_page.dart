import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_git.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

import '../widgets/hermes_git_commit_sheet.dart';

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
        const SizedBox(height: Spacing.sm),
        Row(
          children: [
            Expanded(
              child: ConduitButton(
                key: const ValueKey<String>('hermes-git-commit'),
                text: l10n.hermesGitCommit,
                isSecondary: true,
                isCompact: true,
                onPressed: status.staged == 0
                    ? null
                    : () => showHermesGitCommitSheet(
                        context,
                        path: path,
                        staged: status.staged,
                      ),
              ),
            ),
            if (status.ahead > 0) ...[
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: ConduitButton(
                  key: const ValueKey<String>('hermes-git-push'),
                  text: l10n.hermesGitPushAhead(status.ahead),
                  isSecondary: true,
                  isCompact: true,
                  onPressed: () => _push(path, branch, l10n),
                ),
              ),
            ],
          ],
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
                      InkWell(
                        key: ValueKey<String>('hermes-git-stage-${file.path}'),
                        borderRadius: BorderRadius.circular(IconSize.listItem),
                        onTap: () => _toggleStage(path, file),
                        child: Padding(
                          padding: const EdgeInsets.only(right: Spacing.xs),
                          child: Icon(
                            file.staged && !file.unstaged
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: IconSize.listItem,
                            color: file.staged && !file.unstaged
                                ? theme.success
                                : theme.iconSecondary,
                          ),
                        ),
                      ),
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

  Future<void> _toggleStage(String path, HermesGitFile file) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    final l10n = _l10n(context);
    try {
      if (file.staged && !file.unstaged) {
        await service.unstageGitFile(path: path, file: file.path);
      } else {
        await service.stageGitFile(path: path, file: file.path);
      }
      ref.invalidate(hermesGitStatusProvider(path));
    } catch (error) {
      if (!mounted) return;
      UiUtils.showMessage(context, l10n.hermesGitStageFailed, isError: true);
    }
  }

  Future<void> _push(String path, String branch, AppLocalizations l10n) async {
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: l10n.hermesGitPush,
      message: l10n.hermesGitPushConfirm(branch),
      confirmText: l10n.hermesGitPush,
      cancelText: l10n.cancel,
    );
    if (!confirmed || !mounted) return;
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    try {
      await service.pushGit(path);
      ref.invalidate(hermesGitStatusProvider(path));
      if (!mounted) return;
      UiUtils.showMessage(context, l10n.hermesGitPushed);
    } catch (error) {
      if (!mounted) return;
      final detail = RegExp(r'"detail"\s*:\s*"([^"]{1,300})"')
          .firstMatch(error.toString())
          ?.group(1);
      UiUtils.showMessage(
        context,
        detail ?? l10n.hermesGitPushFailed,
        isError: true,
      );
    }
  }

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
