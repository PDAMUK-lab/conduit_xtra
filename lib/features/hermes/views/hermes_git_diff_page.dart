import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// One file's diff against HEAD, read-only.
class HermesGitDiffPage extends ConsumerWidget {
  const HermesGitDiffPage({super.key, required this.path, required this.file});

  final String path;
  final String file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final diffAsync = ref.watch(
      hermesGitFileDiffProvider((path: path, file: file)),
    );

    return UtilityPageScaffold.settings(
      title: file.split('/').last,
      children: [
        Text(
          file,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.codeStyle.copyWith(color: theme.textSecondary),
        ),
        const SizedBox(height: Spacing.md),
        diffAsync.when(
          data: (diff) {
            if (diff == null || diff.diff.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Center(
                  child: Text(
                    l10n.hermesGitNoDiff,
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                ),
              );
            }
            return Container(
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: theme.groupedSurface,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
              ),
              child: SelectableText(
                diff.diff,
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
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(
              child: Text(
                l10n.hermesGitLoadFailed,
                style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
