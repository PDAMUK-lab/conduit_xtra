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

Future<void> showHermesGitBranchSheet(
  BuildContext context, {
  required String path,
}) => ThemedSheets.showSurface(
  context: context,
  padding: EdgeInsets.zero,
  builder: (_) => HermesGitBranchSheet(path: path),
);

/// Check out another branch.
///
/// Git refuses a switch that would overwrite local changes; the server returns
/// that reason and it is shown here rather than being smoothed over.
class HermesGitBranchSheet extends ConsumerStatefulWidget {
  const HermesGitBranchSheet({super.key, required this.path});

  final String path;

  @override
  ConsumerState<HermesGitBranchSheet> createState() =>
      _HermesGitBranchSheetState();
}

class _HermesGitBranchSheetState extends ConsumerState<HermesGitBranchSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final branches = ref.watch(hermesGitBranchesProvider(widget.path));

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
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
              l10n.hermesGitSwitchBranch,
              style: AppTypography.standard.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: branches.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.hermesGitNoBranches,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  );
                }
                final local = rows.where((b) => !b.isRemote).toList();
                final remote = rows.where((b) => b.isRemote).toList();
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  children: [
                    for (final branch in local)
                      _row(branch, theme, l10n),
                    if (remote.isNotEmpty) ...[
                      const SizedBox(height: Spacing.sm),
                      Text(
                        l10n.hermesGitRemoteBranches,
                        style: AppTypography.labelStyle.copyWith(
                          color: theme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      for (final branch in remote)
                        _row(branch, theme, l10n),
                    ],
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
    HermesGitBranch branch,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    return InkWell(
      key: ValueKey<String>('hermes-git-branch-${branch.name}'),
      onTap: _busy || branch.checkedOut
          ? null
          : () => _switchTo(branch.name, l10n),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Row(
          children: [
            Icon(
              branch.checkedOut ? Icons.check : Icons.commit,
              size: IconSize.listItem,
              color: branch.checkedOut ? theme.success : theme.iconSecondary,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                branch.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.codeStyle.copyWith(
                  color: branch.checkedOut ? theme.textSecondary : theme.textPrimary,
                ),
              ),
            ),
            if (branch.isDefault)
              Text(
                l10n.hermesGitDefaultBranch,
                style: AppTypography.captionStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchTo(String branch, AppLocalizations l10n) async {
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: l10n.hermesGitSwitchBranch,
      message: l10n.hermesGitSwitchConfirm(branch),
      confirmText: l10n.hermesGitSwitchBranch,
      cancelText: l10n.cancel,
    );
    if (!confirmed || !mounted) return;
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _busy = true);
    try {
      await service.switchGitBranch(path: widget.path, branch: branch);
      ref.invalidate(hermesGitStatusProvider(widget.path));
      ref.invalidate(hermesGitBranchesProvider(widget.path));
      if (!mounted || !context.mounted) return;
      UiUtils.showMessage(context, l10n.hermesGitSwitched(branch));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      final detail = RegExp(r'"detail"\s*:\s*"([^"]{1,300})"')
          .firstMatch(error.toString())
          ?.group(1);
      UiUtils.showMessage(
        context,
        detail ?? l10n.hermesGitSwitchFailed,
        isError: true,
      );
    }
  }
}
