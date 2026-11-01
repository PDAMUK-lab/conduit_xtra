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

import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Read and rewrite one text file through `GET/POST /api/fs/*`.
///
/// The server has no conflict detection on write, so saving re-reads the file
/// first: if it changed since it was opened, the user chooses between reloading
/// the newer version and overwriting it. Binary files and previews the server
/// truncated are read-only — saving a truncated preview would silently delete
/// the rest of the file.
class HermesFileEditorPage extends ConsumerStatefulWidget {
  const HermesFileEditorPage({super.key, required this.path});

  final String path;

  @override
  ConsumerState<HermesFileEditorPage> createState() =>
      _HermesFileEditorPageState();
}

class _HermesFileEditorPageState extends ConsumerState<HermesFileEditorPage> {
  final TextEditingController _content = TextEditingController();
  String? _loadedText;
  bool _saving = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final fileAsync = ref.watch(hermesFsTextProvider(widget.path));

    return UtilityPageScaffold.settings(
      title: widget.path.split('/').last,
      children: [
        Text(
          widget.path,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.codeStyle.copyWith(color: theme.textSecondary),
        ),
        const SizedBox(height: Spacing.md),
        fileAsync.when(
          data: (file) {
            if (file == null) {
              return _message(theme, l10n.hermesFileReadFailed, theme.error);
            }
            if (file.binary) {
              return _message(theme, l10n.hermesFileBinary, theme.textSecondary);
            }
            if (file.truncated) {
              return _message(
                theme,
                l10n.hermesFileTruncated,
                theme.textSecondary,
              );
            }
            if (_loadedText != file.text) {
              // First build for this file (or a reload): adopt the server's
              // text without clobbering what is being typed.
              _loadedText = file.text;
              _content.text = file.text;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConduitInput(
                  key: const ValueKey<String>('hermes-file-content'),
                  label: '${file.language} · ${file.byteSize} B',
                  controller: _content,
                  minLines: 16,
                  maxLines: 40,
                ),
                const SizedBox(height: Spacing.lg),
                ConduitButton(
                  key: const ValueKey<String>('hermes-file-save'),
                  text: l10n.hermesFileSave,
                  isFullWidth: true,
                  isLoading: _saving,
                  onPressed: _saving ? null : () => _save(file.text),
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesFileReadFailed, theme.error),
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

  Future<void> _save(String originalText) async {
    final l10n = _l10n(context);
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _saving = true);
    try {
      // Stale-on-disk detection is the client's job: the server happily
      // overwrites. Re-read before writing and let the user decide.
      final latest = await service.fsReadText(widget.path);
      if (!mounted) return;
      if (latest != null && latest.text != originalText) {
        final overwrite = await ThemedDialogs.confirm(
          context,
          title: l10n.hermesFileChangedTitle,
          message: l10n.hermesFileChangedBody,
          confirmText: l10n.hermesFileOverwrite,
          cancelText: l10n.hermesFileReload,
          isDestructive: true,
        );
        if (!overwrite) {
          _loadedText = latest.text;
          _content.text = latest.text;
          if (mounted) setState(() {});
          return;
        }
      }
      await service.fsWriteText(path: widget.path, content: _content.text);
      ref.invalidate(hermesFsTextProvider(widget.path));
      ref.invalidate(hermesFsListingProvider(_directoryOf(widget.path)));
      if (!mounted) return;
      UiUtils.showMessage(context, l10n.hermesFileSaved);
      if (context.canPop()) context.pop();
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(context, l10n.hermesFileSaveFailed, isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _directoryOf(String path) {
    final index = path.lastIndexOf('/');
    if (index < 0) return '/';
    return index == 0 ? '/' : path.substring(0, index);
  }
}
