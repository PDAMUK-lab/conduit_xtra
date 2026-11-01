import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/themed_sheets.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// True when the operator confirmed the restore.
Future<bool?> showHermesRestoreSheet(
  BuildContext context, {
  required String archive,
}) => ThemedSheets.showSurface<bool>(
  context: context,
  padding: EdgeInsets.zero,
  builder: (_) => HermesRestoreSheet(archive: archive),
);

/// Restoring a backup replaces current state and needs the gateway drained, so
/// it asks for the word to be typed and says what will stop working while it
/// runs.
class HermesRestoreSheet extends StatefulWidget {
  const HermesRestoreSheet({super.key, required this.archive});

  final String archive;

  @override
  State<HermesRestoreSheet> createState() => _HermesRestoreSheetState();
}

class _HermesRestoreSheetState extends State<HermesRestoreSheet> {
  final _confirm = TextEditingController();
  String _typed = '';

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;

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
              l10n.hermesRestoreTitle,
              style: AppTypography.standard.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.xs,
              Spacing.md,
              0,
            ),
            child: Text(
              widget.archive.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.codeStyle.copyWith(
                color: theme.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              0,
            ),
            child: Text(
              l10n.hermesRestoreWarning,
              style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.xs,
              Spacing.md,
              0,
            ),
            child: Text(
              l10n.hermesRestoreDrainNote,
              style: AppTypography.captionStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: TextField(
              key: const ValueKey<String>('hermes-restore-confirm'),
              controller: _confirm,
              autocorrect: false,
              enableSuggestions: false,
              style: AppTypography.codeStyle.copyWith(color: theme.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.hermesRestoreType('import'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _typed = value.trim()),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: ConduitButton(
              key: const ValueKey<String>('hermes-restore-submit'),
              text: l10n.hermesRestoreTitle,
              isDestructive: true,
              isFullWidth: true,
              onPressed: _typed == 'import'
                  ? () => Navigator.of(context).pop(true)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
