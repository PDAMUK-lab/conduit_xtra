import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_fs.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/navigation/routes.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// A directory browser over the dashboard's `/api/fs` routes.
///
/// Starts at the agent's `default-cwd` (usually the terminal's working
/// directory) and walks down from there. Tapping a file opens the editor; the
/// server decides what is text, what is binary and what is too large to edit.
class HermesFilesPage extends ConsumerStatefulWidget {
  const HermesFilesPage({super.key});

  @override
  ConsumerState<HermesFilesPage> createState() => _HermesFilesPageState();
}

class _HermesFilesPageState extends ConsumerState<HermesFilesPage> {
  String? _path;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final defaultsAsync = ref.watch(hermesFsDefaultsProvider);
    final path = _path ?? defaultsAsync.asData?.value?.cwd;

    return UtilityPageScaffold.settings(
      title: l10n.hermesFilesTitle,
      children: [
        if (defaultsAsync.asData?.value case final defaults?
            when defaults.branch != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Text(
              defaults.branch!,
              style: AppTypography.captionStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
        if (path == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          _pathBar(path, theme, l10n),
          const SizedBox(height: Spacing.sm),
          ref
              .watch(hermesFsListingProvider(path))
              .when(
                data: (listing) {
                  if (listing == null) {
                    return _message(
                      theme,
                      l10n.hermesFilesLoadFailed,
                      theme.error,
                    );
                  }
                  if (listing.entries.isEmpty) {
                    return _message(
                      theme,
                      listing.error == null
                          ? l10n.hermesFilesEmpty
                          : l10n.hermesFilesLoadFailed,
                      listing.error == null ? theme.textSecondary : theme.error,
                    );
                  }
                  return Column(
                    children: [
                      for (final entry in listing.entries) ...[
                        _entryTile(entry, theme),
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
                    _message(theme, l10n.hermesFilesLoadFailed, theme.error),
              ),
        ],
      ],
    );
  }

  Widget _pathBar(
    String path,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) => Row(
    children: [
      ConduitIconButton(
        key: const ValueKey<String>('hermes-files-up'),
        icon: Icons.arrow_upward_rounded,
        iconColor: theme.iconSecondary,
        tooltip: l10n.hermesFilesUp,
        isCompact: true,
        onPressed: _parentOf(path) == null
            ? null
            : () => setState(() => _path = _parentOf(path)),
      ),
      const SizedBox(width: Spacing.xs),
      Expanded(
        child: Text(
          path,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.codeStyle.copyWith(color: theme.textSecondary),
        ),
      ),
    ],
  );

  Widget _entryTile(HermesFsEntry entry, ConduitThemeExtension theme) =>
      Container(
        decoration: BoxDecoration(
          color: theme.groupedSurface,
          borderRadius: BorderRadius.circular(AppBorderRadius.card),
        ),
        child: InkWell(
          key: ValueKey<String>('hermes-fs-entry-${entry.path}'),
          borderRadius: BorderRadius.circular(AppBorderRadius.card),
          onTap: () {
            if (entry.isDirectory) {
              setState(() => _path = entry.path);
            } else {
              context.push(Routes.hermesFileEditorPath(entry.path));
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Icon(
                  entry.isDirectory
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                  size: 18,
                  color: entry.isDirectory
                      ? theme.buttonPrimary
                      : theme.iconSecondary,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.standard.copyWith(
                      color: theme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

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

  String? _parentOf(String path) {
    if (path == '/' || path.isEmpty) return null;
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index < 0) return null;
    return index == 0 ? '/' : trimmed.substring(0, index);
  }
}
