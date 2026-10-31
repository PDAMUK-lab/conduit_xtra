import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Read and rewrite one skill's SKILL.md, or create a new skill.
///
/// Editing is a full rewrite through `PUT /api/skills/content`, exactly what
/// the dashboard editor does: there is no patch endpoint, and a partial merge
/// would be worse than showing the whole document.
class HermesSkillEditorPage extends ConsumerStatefulWidget {
  const HermesSkillEditorPage({super.key, this.skillName});

  /// Null creates a new skill.
  final String? skillName;

  @override
  ConsumerState<HermesSkillEditorPage> createState() =>
      _HermesSkillEditorPageState();
}

class _HermesSkillEditorPageState extends ConsumerState<HermesSkillEditorPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _content = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  bool get _isCreate => widget.skillName == null;

  @override
  void initState() {
    super.initState();
    _name.text = widget.skillName ?? '';
    if (_isCreate) {
      _content.text = _newSkillTemplate();
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) {
      setState(() {
        _loading = false;
        _loadError = _l10n(context).hermesSkillsLoadFailed;
      });
      return;
    }
    try {
      final content = await service.skillContent(widget.skillName!);
      if (!mounted) return;
      setState(() {
        _content.text = content;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _l10n(context).hermesSkillsLoadFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    return UtilityPageScaffold.settings(
      title: _isCreate ? l10n.hermesSkillCreateTitle : l10n.hermesSkillEditTitle,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(
              child: Text(
                _loadError!,
                style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
              ),
            ),
          )
        else ...[
          if (_isCreate) ...[
            ConduitInput(
              key: const ValueKey<String>('hermes-skill-name'),
              label: l10n.hermesSkillNameLabel,
              controller: _name,
              hint: 'my-skill',
            ),
            const SizedBox(height: Spacing.md),
            ConduitInput(
              key: const ValueKey<String>('hermes-skill-category'),
              label: l10n.hermesSkillCategoryLabel,
              controller: _category,
            ),
            const SizedBox(height: Spacing.md),
          ],
          ConduitInput(
            key: const ValueKey<String>('hermes-skill-content'),
            label: l10n.hermesSkillContentLabel,
            controller: _content,
            minLines: 12,
            maxLines: 24,
          ),
          const SizedBox(height: Spacing.lg),
          ConduitButton(
            key: const ValueKey<String>('hermes-skill-save'),
            text: l10n.hermesSkillSave,
            isFullWidth: true,
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    final l10n = _l10n(context);
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _saving = true);
    try {
      if (_isCreate) {
        final name = _name.text.trim();
        if (name.isEmpty) {
          throw const FormatException('A skill needs a name.');
        }
        await service.createSkill(
          name: name,
          content: _content.text,
          category: _category.text,
        );
      } else {
        await service.updateSkillContent(
          name: widget.skillName!,
          content: _content.text,
        );
      }
      ref.invalidate(hermesDashboardSkillsProvider);
      if (!mounted) return;
      UiUtils.showMessage(context, l10n.hermesSkillSaved);
      if (context.canPop()) context.pop();
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(context, l10n.hermesSkillSaveFailed, isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Minimal valid front matter so a new skill shows up with its name and
/// description instead of being rejected for an empty document.
String _newSkillTemplate() => '''
---
name: my-skill
description: What this skill does, in one line.
---

# My skill

## When to use

Describe the trigger for this skill.

## Steps

1. First step.
''';
