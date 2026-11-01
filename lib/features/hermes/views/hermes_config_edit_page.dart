import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yaml/yaml.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_yaml_diff.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

String _normalise(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\s+$'), '');

/// Full-document editor for the server's `config.yaml`.
///
/// `PUT /api/config/raw` replaces the file (`merge_existing=False`), so the
/// order is deliberate: parse locally, show the line diff, require the file
/// name typed, write, then read the file back and compare. A mismatch is
/// reported as a failure even when the write returned 200.
class HermesConfigEditPage extends ConsumerStatefulWidget {
  const HermesConfigEditPage({super.key, this.restoreText});

  /// Text to open with (the pre-save document, for a restore).
  final String? restoreText;

  @override
  ConsumerState<HermesConfigEditPage> createState() =>
      _HermesConfigEditPageState();
}

class _HermesConfigEditPageState extends ConsumerState<HermesConfigEditPage> {
  final _editor = TextEditingController();
  final _confirm = TextEditingController();
  bool _seeded = false;
  bool _review = false;
  bool _saving = false;
  String _confirmText = '';
  String? _error;

  @override
  void dispose() {
    _editor.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final configAsync = ref.watch(hermesRawConfigProvider);

    return configAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(l10n.hermesConfigEditTitle)),
        body: Center(
          child: Text(
            l10n.hermesConfigLoadFailed,
            style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
          ),
        ),
      ),
      data: (config) {
        if (config == null) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.hermesConfigEditTitle)),
            body: Center(
              child: Text(
                l10n.hermesConfigNoFile,
                style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
              ),
            ),
          );
        }
        if (!_seeded) {
          _seeded = true;
          _editor.text = widget.restoreText ?? config.yaml;
        }
        final basename = config.path.split('/').last;
        // The diff is always against what is on disk now, including when the
        // editor was opened from a stored previous version.
        final original = config.yaml;
        final diff = diffYamlDocuments(original, _editor.text);
        final canSave =
            _review &&
            !_saving &&
            !diff.isEmpty &&
            _confirmText.trim() == basename;

        return UtilityPageScaffold.settings(
          title: l10n.hermesConfigEditTitle,
          trailing: ConduitButton(
            key: const ValueKey<String>('hermes-config-review'),
            text: l10n.hermesConfigReview,
            isSecondary: true,
            isCompact: true,
            onPressed: _saving
                ? null
                : () {
                    final problem = _validate(_editor.text);
                    setState(() {
                      _error = problem;
                      _review = problem == null;
                    });
                  },
          ),
          children: [
            Text(
              l10n.hermesConfigEditSubtitle,
              style: AppTypography.bodySmallStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              l10n.hermesConfigFormatWarning,
              style: AppTypography.captionStyle.copyWith(color: theme.error),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              config.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.codeStyle.copyWith(
                color: theme.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: const ValueKey<String>('hermes-config-editor'),
              controller: _editor,
              minLines: 14,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              style: AppTypography.codeStyle.copyWith(
                color: theme.textPrimary,
                fontSize: 11,
              ),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {
                _review = false;
                _error = null;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                _error!,
                style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
              ),
            ],
            if (_review) ...[
              const SizedBox(height: Spacing.lg),
              _diffSection(diff, theme, l10n),
              const SizedBox(height: Spacing.lg),
              Text(
                l10n.hermesConfigConfirmHint(basename),
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              TextField(
                key: const ValueKey<String>('hermes-config-confirm'),
                controller: _confirm,
                autocorrect: false,
                enableSuggestions: false,
                style: AppTypography.codeStyle.copyWith(
                  color: theme.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: basename,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _confirmText = value),
              ),
              const SizedBox(height: Spacing.md),
              ConduitButton(
                key: const ValueKey<String>('hermes-config-save'),
                text: l10n.hermesConfigSave,
                isDestructive: false,
                isFullWidth: true,
                onPressed: canSave ? () => _save(_editor.text, original) : null,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _diffSection(
    HermesYamlDiff diff,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.hermesConfigDiffCounts(diff.added, diff.removed),
          style: AppTypography.labelStyle.copyWith(
            color: theme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Container(
          padding: const EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: theme.groupedSurface,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in diff.lines)
                Text(
                  line.isGap
                      ? '…'
                      : '${switch (line.kind) {
                          HermesDiffKind.added => '+',
                          HermesDiffKind.removed => '−',
                          HermesDiffKind.context => ' ',
                        }}${line.text}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.codeStyle.copyWith(
                    fontSize: 11,
                    color: switch (line.kind) {
                      HermesDiffKind.added => theme.success,
                      HermesDiffKind.removed => theme.error,
                      HermesDiffKind.context => theme.textSecondary,
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Local parse before the network call. The server parses again and is the
  /// authority; this only spares a round trip on an obvious mistake.
  String? _validate(String text) {
    final l10n = _l10n(context);
    if (text.trim().isEmpty) return l10n.hermesConfigNotMapping;
    try {
      final parsed = loadYaml(text);
      if (parsed is! Map) return l10n.hermesConfigNotMapping;
    } on YamlException catch (error) {
      return l10n.hermesConfigInvalidYaml(error.message);
    }
    return null;
  }

  Future<void> _save(String text, String original) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    final l10n = _l10n(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await service.saveRawConfig(text);
      final readBack = await service.rawConfig();
      if (!mounted) return;
      // The server re-serialises on save, so compare the parsed documents when
      // both parse: a formatting-only difference is a successful write.
      final sent = canonicalYaml(text);
      final stored = readBack == null ? null : canonicalYaml(readBack.yaml);
      final matches = sent != null && stored != null
          ? sent == stored
          : readBack != null && _normalise(readBack.yaml) == _normalise(text);
      if (readBack == null || !matches) {
        setState(() {
          _saving = false;
          _error = l10n.hermesConfigVerifyFailed;
        });
        return;
      }
      ref.read(hermesConfigUndoProvider.notifier).remember(original);
      ref.invalidate(hermesRawConfigProvider);
      if (context.mounted) {
        UiUtils.showMessage(context, l10n.hermesConfigSaved);
        context.pop();
      }
    } catch (error) {
      if (!mounted) return;
      final detail = RegExp(
        r'"detail"\s*:\s*"([^"]{1,400})"',
      ).firstMatch(error.toString())?.group(1);
      setState(() {
        _saving = false;
        _error = detail ?? l10n.hermesConfigSaveFailed;
      });
    }
  }
}
