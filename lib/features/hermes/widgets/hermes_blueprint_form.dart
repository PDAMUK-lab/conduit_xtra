import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/themed_sheets.dart';

import 'package:conduit_core/features/hermes/models/hermes_blueprint.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

Future<bool?> showHermesBlueprintForm(
  BuildContext context,
  HermesBlueprint blueprint,
) => ThemedSheets.showSurface<bool>(
  context: context,
  padding: EdgeInsets.zero,
  builder: (_) => HermesBlueprintForm(blueprint: blueprint),
);

/// Fill a blueprint's slots and create the job it describes.
///
/// The form never invents values: enums use the server's options, and the
/// schedule template is fixed by the blueprint. The server validates and
/// answers 422 with a message for a bad slot, which is shown inline.
class HermesBlueprintForm extends ConsumerStatefulWidget {
  const HermesBlueprintForm({super.key, required this.blueprint});

  final HermesBlueprint blueprint;

  @override
  ConsumerState<HermesBlueprintForm> createState() =>
      _HermesBlueprintFormState();
}

class _HermesBlueprintFormState extends ConsumerState<HermesBlueprintForm> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, String> _choice = {};
  final Map<String, bool> _customMode = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final field in widget.blueprint.fields) {
      if (field.isEnum) {
        final fallback = field.defaultValue;
        final selected =
            fallback != null && field.options.contains(fallback)
            ? fallback
            : (field.options.isNotEmpty ? field.options.first : '');
        _choice[field.name] = selected;
        _customMode[field.name] = false;
      } else {
        _text[field.name] = TextEditingController(
          text: field.defaultValue ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final blueprint = widget.blueprint;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
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
              blueprint.title,
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
              blueprint.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.captionStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final field in blueprint.fields) ...[
                    _field(field, theme, l10n),
                    const SizedBox(height: Spacing.md),
                  ],
                  if (_error != null)
                    Text(
                      _error!,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: ConduitButton(
              key: const ValueKey<String>('hermes-blueprint-submit'),
              text: l10n.hermesBlueprintUse,
              isFullWidth: true,
              onPressed: _busy || !_complete ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    HermesBlueprintField field,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    if (field.isEnum) {
      final choice = _choice[field.name] ?? '';
      final custom = _customMode[field.name] == true || !field.strict && choice == '__custom__';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey<String>('hermes-blueprint-${field.name}'),
            initialValue: custom ? (field.strict ? choice : '__custom__') : choice,
            decoration: InputDecoration(
              labelText: field.label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final option in field.options)
                DropdownMenuItem<String>(value: option, child: Text(option)),
              if (!field.strict)
                DropdownMenuItem<String>(
                  value: '__custom__',
                  child: Text(l10n.hermesBlueprintCustom),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                if (value == '__custom__') {
                  _customMode[field.name] = true;
                } else {
                  _customMode[field.name] = false;
                  _choice[field.name] = value;
                }
                _error = null;
              });
            },
          ),
          if (custom || (!field.strict && _customMode[field.name] == true)) ...[
            const SizedBox(height: Spacing.xs),
            TextField(
              key: ValueKey<String>('hermes-blueprint-${field.name}-custom'),
              controller: _text.putIfAbsent(
                field.name,
                () => TextEditingController(
                  text: field.defaultValue ?? '',
                ),
              ),
              style: AppTypography.codeStyle.copyWith(color: theme.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.hermesBlueprintCustom,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
          if (field.help.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xxs),
              child: Text(
                field.help,
                style: AppTypography.captionStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ),
        ],
      );
    }

    final controller = _text[field.name];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: ValueKey<String>('hermes-blueprint-${field.name}'),
          controller: controller,
          autocorrect: false,
          enableSuggestions: false,
          style: AppTypography.codeStyle.copyWith(color: theme.textPrimary),
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.isTime ? 'HH:MM' : null,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
        if (field.help.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xxs),
            child: Text(
              field.help,
              style: AppTypography.captionStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  String _valueOf(HermesBlueprintField field) {
    if (field.isEnum) {
      if (_customMode[field.name] == true) {
        return _text[field.name]?.text.trim() ?? '';
      }
      return _choice[field.name] ?? '';
    }
    return _text[field.name]?.text.trim() ?? '';
  }

  bool get _complete => widget.blueprint.fields.every((field) {
    if (field.optional) return true;
    final value = _valueOf(field);
    if (value.isEmpty) return false;
    if (field.isTime) {
      return RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(value);
    }
    return true;
  });

  Future<void> _submit() async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    final l10n = _l10n(context);
    setState(() => _busy = true);
    try {
      await service.instantiateBlueprint(
        key: widget.blueprint.key,
        values: {
          for (final field in widget.blueprint.fields)
            field.name: _valueOf(field),
        }..removeWhere((_, value) => value.isEmpty),
      );
      ref.invalidate(hermesJobsProvider);
      if (!mounted) return;
      UiUtils.showMessage(context, l10n.hermesBlueprintCreated);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = RegExp(r'"detail"\s*:\s*"([^"]{1,400})"')
                .firstMatch(error.toString())
                ?.group(1) ??
            l10n.hermesBlueprintCreateFailed;
      });
    }
  }
}
