import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/themed_sheets.dart';

import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

Future<void> showHermesGitCommitSheet(
  BuildContext context, {
  required String path,
  required int staged,
}) => ThemedSheets.showSurface(
  context: context,
  padding: EdgeInsets.zero,
  builder: (_) => HermesGitCommitSheet(path: path, staged: staged),
);

/// Commit what is staged, optionally pushing after.
///
/// The message is required and the push toggle starts off: committing writes
/// history, pushing publishes it, and neither should ride on one tap.
class HermesGitCommitSheet extends ConsumerStatefulWidget {
  const HermesGitCommitSheet({
    super.key,
    required this.path,
    required this.staged,
  });

  final String path;
  final int staged;

  @override
  ConsumerState<HermesGitCommitSheet> createState() =>
      _HermesGitCommitSheetState();
}

class _HermesGitCommitSheetState extends ConsumerState<HermesGitCommitSheet> {
  final _message = TextEditingController();
  bool _push = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final canCommit =
        !_busy && widget.staged > 0 && _message.text.trim().isNotEmpty;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.58,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              0,
            ),
            child: Text(
              l10n.hermesGitCommitTitle,
              style: AppTypography.standard.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.xxs,
              Spacing.md,
              0,
            ),
            child: Text(
              widget.staged > 0
                  ? l10n.hermesGitStagedCount(widget.staged)
                  : l10n.hermesGitNoStaged,
              style: AppTypography.captionStyle.copyWith(
                color: widget.staged > 0 ? theme.textSecondary : theme.error,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: TextField(
              key: const ValueKey<String>('hermes-git-commit-message'),
              controller: _message,
              minLines: 3,
              maxLines: 6,
              autocorrect: false,
              style: AppTypography.codeStyle.copyWith(color: theme.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.hermesGitCommitMessage,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          SwitchListTile.adaptive(
            key: const ValueKey<String>('hermes-git-commit-push'),
            value: _push,
            onChanged: _busy ? null : (value) => setState(() => _push = value),
            title: Text(
              l10n.hermesGitCommitPush,
              style: AppTypography.bodySmallStyle.copyWith(
                color: theme.textPrimary,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Text(
                _error!,
                style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: ConduitButton(
              key: const ValueKey<String>('hermes-git-commit-submit'),
              text: l10n.hermesGitCommit,
              isFullWidth: true,
              onPressed: canCommit ? _commit : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _commit() async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    final l10n = _l10n(context);
    setState(() => _busy = true);
    try {
      await service.commitGit(
        path: widget.path,
        message: _message.text.trim(),
        push: _push,
      );
      ref.invalidate(hermesGitStatusProvider(widget.path));
      if (!mounted || !context.mounted) return;
      UiUtils.showMessage(context, l10n.hermesGitCommitted);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = RegExp(r'"detail"\s*:\s*"([^"]{1,300})"')
                .firstMatch(error.toString())
                ?.group(1) ??
            l10n.hermesGitCommitFailed;
      });
    }
  }
}
