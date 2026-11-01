import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../../shared/widgets/themed_sheets.dart';

import 'package:conduit_core/features/hermes/models/hermes_git.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Returns the worktree path the operator chose, if any.
Future<String?> showHermesGitWorktreesSheet(
  BuildContext context, {
  required String path,
  required String current,
}) => ThemedSheets.showSurface<String>(
  context: context,
  padding: EdgeInsets.zero,
  builder: (_) =>
      HermesGitWorktreesSheet(path: path, currentPath: current),
);

/// Worktrees of one repository: open another checkout, or remove one.
class HermesGitWorktreesSheet extends ConsumerStatefulWidget {
  const HermesGitWorktreesSheet({
    super.key,
    required this.path,
    required this.currentPath,
  });

  final String path;
  final String currentPath;

  @override
  ConsumerState<HermesGitWorktreesSheet> createState() =>
      _HermesGitWorktreesSheetState();
}

class _HermesGitWorktreesSheetState
    extends ConsumerState<HermesGitWorktreesSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final trees = ref.watch(hermesGitWorktreesProvider(widget.path));

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              Spacing.xs,
            ),
            child: Text(
              l10n.hermesGitWorktrees,
              style: AppTypography.standard.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: trees.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.hermesGitNoWorktrees,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  children: [
                    for (final tree in rows) _row(tree, theme, l10n),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  l10n.hermesGitLoadFailed,
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: theme.error,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    HermesGitWorktree tree,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    final isCurrent = tree.path == widget.currentPath;
    return InkWell(
      key: ValueKey<String>('hermes-git-worktree-${tree.path}'),
      onTap: () => Navigator.of(context).pop(tree.path),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Row(
          children: [
            Icon(
              tree.isMain ? Icons.home_outlined : Icons.account_tree_outlined,
              size: IconSize.listItem,
              color: isCurrent ? theme.success : theme.iconSecondary,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tree.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.codeStyle.copyWith(
                      color: theme.textPrimary,
                    ),
                  ),
                  if (tree.branch != null)
                    Text(
                      tree.branch!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (!tree.isMain)
              IconButton(
                key: ValueKey<String>('hermes-git-worktree-remove-${tree.path}'),
                tooltip: l10n.hermesGitRemoveWorktree,
                icon: Icon(
                  Icons.delete_outline,
                  size: IconSize.listItem,
                  color: theme.iconSecondary,
                ),
                onPressed: _busy ? null : () => _remove(tree, l10n),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(HermesGitWorktree tree, AppLocalizations l10n) async {
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: l10n.hermesGitRemoveWorktree,
      message: l10n.hermesGitRemoveWorktreeConfirm(tree.path),
      confirmText: l10n.hermesGitRemoveWorktree,
      cancelText: l10n.cancel,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _busy = true);
    try {
      await service.removeGitWorktree(
        path: widget.path,
        worktreePath: tree.path,
      );
      ref.invalidate(hermesGitWorktreesProvider(widget.path));
      if (!mounted || !context.mounted) return;
      UiUtils.showMessage(context, l10n.hermesGitWorktreeRemoved);
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      final detail = RegExp(r'"detail"\s*:\s*"([^"]{1,300})"')
          .firstMatch(error.toString())
          ?.group(1);
      UiUtils.showMessage(
        context,
        detail ?? l10n.hermesGitWorktreeRemoveFailed,
        isError: true,
      );
    }
  }
}
