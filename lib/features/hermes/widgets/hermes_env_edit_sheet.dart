import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../../shared/widgets/themed_sheets.dart';

import 'package:conduit_core/features/hermes/models/hermes_config_view.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

Future<void> showHermesEnvEditSheet(
  BuildContext context,
  HermesEnvVar variable,
) => ThemedSheets.showSurface(
  context: context,
  padding: EdgeInsets.zero,
  builder: (_) => HermesEnvEditSheet(variable: variable),
);

/// Edit one environment key.
///
/// Values are entered here and sent once; the app never displays or stores a
/// stored secret — only the server's redacted preview. The server writes
/// `.env` and reconciles any config.yaml copy of the same key.
class HermesEnvEditSheet extends ConsumerStatefulWidget {
  const HermesEnvEditSheet({super.key, required this.variable});

  final HermesEnvVar variable;

  @override
  ConsumerState<HermesEnvEditSheet> createState() => _HermesEnvEditSheetState();
}

class _HermesEnvEditSheetState extends ConsumerState<HermesEnvEditSheet> {
  final _value = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final env = widget.variable;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
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
              env.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.codeStyle.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (env.isSet && env.redactedValue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.xxs,
                Spacing.md,
                0,
              ),
              child: Text(
                l10n.hermesEnvCurrentlySet(env.redactedValue),
                style: AppTypography.captionStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ),
          if (env.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.xs,
                Spacing.md,
                0,
              ),
              child: Text(
                env.description,
                style: AppTypography.captionStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: TextField(
              key: const ValueKey<String>('hermes-env-value'),
              controller: _value,
              obscureText: env.isPassword,
              autocorrect: false,
              enableSuggestions: false,
              style: AppTypography.codeStyle.copyWith(color: theme.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.hermesEnvValueHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Text(
              l10n.hermesEnvWriteNote,
              style: AppTypography.captionStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.xs,
                Spacing.md,
                0,
              ),
              child: Text(
                _error!,
                style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              children: [
                ConduitButton(
                  key: const ValueKey<String>('hermes-env-save'),
                  text: l10n.hermesEnvSave,
                  isFullWidth: true,
                  onPressed: _busy || _value.text.trim().isEmpty
                      ? null
                      : _save,
                ),
                if (env.isSet) ...[
                  const SizedBox(height: Spacing.xs),
                  ConduitButton(
                    key: const ValueKey<String>('hermes-env-remove'),
                    text: l10n.hermesEnvRemove,
                    isSecondary: true,
                    isDestructive: true,
                    isFullWidth: true,
                    onPressed: _busy ? null : _remove,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    final l10n = _l10n(context);
    setState(() => _busy = true);
    try {
      await service.setEnvVar(
        key: widget.variable.name,
        value: _value.text.trim(),
      );
      ref.invalidate(hermesEnvVarsProvider);
      if (!mounted || !context.mounted) return;
      UiUtils.showMessage(context, l10n.hermesEnvSaved);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _detail(error) ?? l10n.hermesEnvSaveFailed;
      });
    }
  }

  Future<void> _remove() async {
    final l10n = _l10n(context);
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: l10n.hermesEnvRemove,
      message: l10n.hermesEnvConfirmRemove(widget.variable.name),
      confirmText: l10n.hermesEnvRemove,
      cancelText: l10n.cancel,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _busy = true);
    try {
      await service.deleteEnvVar(widget.variable.name);
      ref.invalidate(hermesEnvVarsProvider);
      if (!mounted || !context.mounted) return;
      UiUtils.showMessage(context, l10n.hermesEnvSaved);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _detail(error) ?? l10n.hermesEnvSaveFailed;
      });
    }
  }

  String? _detail(Object error) => RegExp(
    r'"detail"\s*:\s*"([^"]{1,300})"',
  ).firstMatch(error.toString())?.group(1);
}
