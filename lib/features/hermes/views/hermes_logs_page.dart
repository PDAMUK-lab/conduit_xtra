import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_logs.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// A tail of one server log, filtered by level and free text server-side.
///
/// Read-only. The server caps the tail at 500 lines and rejects unknown file
/// or component names, so the page offers only the files it knows exist.
class HermesLogsPage extends ConsumerStatefulWidget {
  const HermesLogsPage({super.key});

  @override
  ConsumerState<HermesLogsPage> createState() => _HermesLogsPageState();
}

class _HermesLogsPageState extends ConsumerState<HermesLogsPage> {
  final TextEditingController _search = TextEditingController();
  String _file = 'agent';
  String? _level;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final tailAsync = ref.watch(
      hermesLogTailProvider((
        file: _file,
        lines: 300,
        level: _level,
        component: null,
        search: _query,
      )),
    );

    return UtilityPageScaffold.settings(
      title: l10n.hermesLogsTitle,
      onRefresh: () async {
        ref.invalidate(hermesLogTailProvider);
      },
      children: [
        Text(
          l10n.hermesLogsSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xxs,
          children: [
            for (final file in hermesLogFiles)
              ChoiceChip(
                key: ValueKey<String>('hermes-log-file-${file.key}'),
                label: Text(file.label),
                selected: _file == file.key,
                onSelected: (_) => setState(() => _file = file.key),
              ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: Spacing.sm,
          children: [
            for (final level in const ['ALL', 'INFO', 'WARNING', 'ERROR'])
              ChoiceChip(
                key: ValueKey<String>('hermes-log-level-$level'),
                label: Text(level),
                selected: (_level ?? 'ALL') == level,
                onSelected: (_) => setState(
                  () => _level = level == 'ALL' ? null : level,
                ),
              ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        ConduitInput(
          hint: l10n.hermesLogsSearch,
          controller: _search,
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: Spacing.lg),
        tailAsync.when(
          data: (tail) {
            if (tail == null) {
              return _message(theme, l10n.hermesLogsLoadFailed, theme.error);
            }
            if (tail.lines.isEmpty) {
              return _message(theme, l10n.hermesLogsEmpty, theme.textSecondary);
            }
            return Container(
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: theme.groupedSurface,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
              ),
              child: SelectableText(
                tail.lines.join('\n'),
                style: AppTypography.codeStyle.copyWith(
                  color: theme.textPrimary,
                  fontSize: 11,
                ),
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesLogsLoadFailed, theme.error),
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
