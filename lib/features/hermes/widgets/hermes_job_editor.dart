import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/themed_dialogs.dart';

import 'package:conduit_core/features/hermes/models/hermes_delivery_target.dart';
import 'package:conduit_core/features/hermes/models/hermes_job.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/utils/hermes_schedule_validation.dart';

/// Shows the create/edit dialog for a scheduled Hermes job and returns the
/// entered name, prompt, and schedule, or null if cancelled.
Future<({String name, String prompt, String schedule, String deliver})?>
showHermesJobEditor(
  BuildContext context, {
  String? initialName,
  String? initialPrompt,
  String? initialSchedule,
  String? initialDeliver,
}) {
  return ThemedDialogs.showCustom<
    ({String name, String prompt, String schedule, String deliver})
  >(
    context: context,
    builder: (context) => _HermesJobEditorDialog(
      initialName: initialName,
      initialPrompt: initialPrompt,
      initialSchedule: initialSchedule,
      initialDeliver: initialDeliver,
    ),
  );
}

class _HermesJobEditorDialog extends ConsumerStatefulWidget {
  const _HermesJobEditorDialog({
    this.initialName,
    this.initialPrompt,
    this.initialSchedule,
    this.initialDeliver,
  });

  final String? initialName;
  final String? initialPrompt;
  final String? initialSchedule;
  final String? initialDeliver;

  @override
  ConsumerState<_HermesJobEditorDialog> createState() =>
      _HermesJobEditorDialogState();
}

class _HermesJobEditorDialogState extends ConsumerState<_HermesJobEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late final TextEditingController _schedule;
  late String _deliver;
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _prompt = TextEditingController(text: widget.initialPrompt ?? '');
    _schedule = TextEditingController(
      text: widget.initialSchedule ?? '0 9 * * *',
    );
    _deliver = widget.initialDeliver ?? 'local';
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _schedule.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final prompt = _prompt.text.trim();
    final schedule = _schedule.text.trim();
    if (!hermesJobDraftIsValid(
      validateHermesJobDraft(name: name, prompt: prompt, schedule: schedule),
    )) {
      setState(() => _showErrors = true);
      return;
    }
    Navigator.of(context).pop((
      name: name,
      prompt: prompt,
      schedule: schedule,
      deliver: _deliver,
    ));
  }

  /// Where the job's result goes. Targets come from the server so a platform
  /// without a cron home channel is shown as unusable rather than offered.
  Widget _deliveryPicker(
    AppLocalizations l10n,
    ConduitThemeExtension theme,
  ) {
    final targets = ref.watch(hermesDeliveryTargetsProvider).asData?.value;
    final options = targets == null || targets.isEmpty
        ? const [HermesDeliveryTarget(id: 'local', name: 'Local (save only)')]
        : targets;
    final known = options.any((t) => t.id == _deliver);
    final selected = known ? _deliver : options.first.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey<String>('hermes-job-deliver'),
          initialValue: selected,
          decoration: InputDecoration(
            labelText: l10n.hermesJobDeliverLabel,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final target in options)
              DropdownMenuItem<String>(
                value: target.id,
                child: Text(
                  target.homeTargetSet
                      ? target.name
                      : '${target.name} — ${l10n.hermesJobDeliverNoChannel}',
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: target.homeTargetSet
                        ? theme.textPrimary
                        : theme.error,
                  ),
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _deliver = value);
          },
        ),
        const SizedBox(height: Spacing.xxs),
        Text(
          l10n.hermesJobDeliverHelp,
          style: AppTypography.captionStyle.copyWith(color: theme.textSecondary),
        ),
      ],
    );
  }

  String? _errorText(
    AppLocalizations l10n,
    HermesJobFieldError? error, {
    int maximum = 0,
  }) => switch (_showErrors ? error : null) {
    null => null,
    HermesJobFieldError.required => l10n.requiredFieldHelper,
    HermesJobFieldError.tooLong => l10n.hermesJobTooLong(maximum),
    HermesJobFieldError.invalidSchedule => l10n.hermesJobScheduleInvalid,
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final isEditing = widget.initialPrompt != null;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    final errors = validateHermesJobDraft(
      name: _name.text,
      prompt: _prompt.text,
      schedule: _schedule.text,
    );

    return ThemedDialogs.buildBase(
      context: context,
      title: isEditing ? l10n.hermesJobEditorEditTitle : l10n.hermesJobNew,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConduitInput(
              label: l10n.name,
              hint: l10n.hermesJobNameHint,
              controller: _name,
              errorText: _errorText(
                l10n,
                errors.name,
                maximum: kMaxHermesJobNameCharacters,
              ),
              onChanged: (_) {
                if (_showErrors) setState(() {});
              },
            ),
            const SizedBox(height: Spacing.md),
            ConduitInput(
              label: l10n.hermesJobPromptLabel,
              hint: l10n.hermesJobPromptHint,
              controller: _prompt,
              minLines: 2,
              maxLines: 5,
              errorText: _errorText(
                l10n,
                errors.prompt,
                maximum: kMaxHermesJobPromptCharacters,
              ),
              onChanged: (_) {
                if (_showErrors) setState(() {});
              },
            ),
            const SizedBox(height: Spacing.md),
            ConduitInput(
              label: l10n.hermesJobScheduleLabel,
              hint: l10n.hermesJobScheduleHint,
              controller: _schedule,
              errorText: _errorText(
                l10n,
                errors.schedule,
                maximum: kMaxHermesJobScheduleCharacters,
              ),
              onChanged: (_) {
                if (_showErrors) setState(() {});
              },
            ),
            const SizedBox(height: Spacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.hermesJobScheduleHelp,
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            _deliveryPicker(l10n, theme),
          ],
        ),
      ),
      actions: [
        ConduitTextButton(
          onPressed: () => Navigator.of(context).pop(),
          text: l10n.cancel,
        ),
        ConduitTextButton(text: l10n.save, onPressed: _save, isPrimary: true),
      ],
    );
  }
}
