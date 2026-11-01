import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// One profile: its soul, description, main model, and whether it is the
/// sticky active profile.
///
/// Rename, delete, export and import are deliberately absent — they move
/// directories on the server and belong on a desktop, not a phone.
class HermesProfilePage extends ConsumerStatefulWidget {
  const HermesProfilePage({super.key, required this.name});

  final String name;

  @override
  ConsumerState<HermesProfilePage> createState() => _HermesProfilePageState();
}

class _HermesProfilePageState extends ConsumerState<HermesProfilePage> {
  final TextEditingController _soul = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _provider = TextEditingController();
  final TextEditingController _model = TextEditingController();
  bool _loaded = false;
  bool _savingProfile = false;
  bool _savingModel = false;
  bool _settingActive = false;

  @override
  void dispose() {
    _soul.dispose();
    _description.dispose();
    _provider.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final soulAsync = ref.watch(hermesProfileSoulProvider(widget.name));
    final profiles = ref.watch(hermesProfileListProvider).asData?.value;
    final active = ref.watch(hermesActiveProfileProvider).asData?.value;
    final summary = profiles
        ?.where((profile) => profile.name == widget.name)
        .firstOrNull;

    if (!_loaded && summary != null) {
      _description.text = summary.description;
      _provider.text = summary.provider ?? '';
      _model.text = summary.model ?? '';
      _loaded = true;
    }

    return UtilityPageScaffold.settings(
      title: widget.name,
      children: [
        if (summary != null && summary.modelLabel.isNotEmpty)
          Text(
            summary.modelLabel,
            style: AppTypography.bodySmallStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
        const SizedBox(height: Spacing.md),
        if (active?.active != widget.name)
          ConduitButton(
            key: const ValueKey<String>('hermes-profile-set-active'),
            text: l10n.hermesProfileSetActive,
            icon: Icons.check_circle_outline,
            isFullWidth: true,
            isLoading: _settingActive,
            onPressed: _settingActive ? null : _setActive,
          ),
        const SizedBox(height: Spacing.lg),
        Text(
          l10n.hermesProfileSoul,
          style: AppTypography.labelStyle.copyWith(
            color: theme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        soulAsync.when(
          data: (soul) {
            if (soul == null) {
              return Text(
                l10n.hermesProfilesLoadFailed,
                style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
              );
            }
            if (_soul.text.isEmpty && soul.content.isNotEmpty) {
              _soul.text = soul.content;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConduitInput(
                  key: const ValueKey<String>('hermes-profile-soul'),
                  label: soul.exists ? 'SOUL.md' : 'SOUL.md (new)',
                  controller: _soul,
                  minLines: 12,
                  maxLines: 30,
                ),
                const SizedBox(height: Spacing.md),
                ConduitInput(
                  key: const ValueKey<String>('hermes-profile-description'),
                  label: l10n.hermesProfileDescription,
                  controller: _description,
                  maxLines: 3,
                ),
                const SizedBox(height: Spacing.md),
                ConduitButton(
                  key: const ValueKey<String>('hermes-profile-save'),
                  text: l10n.hermesProfileSave,
                  isFullWidth: true,
                  isLoading: _savingProfile,
                  onPressed: _savingProfile ? null : _saveProfile,
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(
            l10n.hermesProfilesLoadFailed,
            style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          l10n.hermesProfileModel,
          style: AppTypography.labelStyle.copyWith(
            color: theme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        ConduitInput(
          key: const ValueKey<String>('hermes-profile-provider'),
          label: l10n.hermesProfileProvider,
          controller: _provider,
        ),
        const SizedBox(height: Spacing.sm),
        ConduitInput(
          key: const ValueKey<String>('hermes-profile-model'),
          label: l10n.hermesProfileModel,
          controller: _model,
        ),
        const SizedBox(height: Spacing.md),
        ConduitButton(
          key: const ValueKey<String>('hermes-profile-save-model'),
          text: l10n.hermesProfileSave,
          isSecondary: true,
          isFullWidth: true,
          isLoading: _savingModel,
          onPressed: _savingModel ? null : _saveModel,
        ),
      ],
    );
  }

  Future<void> _saveProfile() async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _savingProfile = true);
    try {
      await service.updateProfileSoul(name: widget.name, content: _soul.text);
      await service.updateProfileDescription(
        name: widget.name,
        description: _description.text,
      );
      ref.invalidate(hermesProfileSoulProvider(widget.name));
      ref.invalidate(hermesProfileListProvider);
      if (!mounted) return;
      UiUtils.showMessage(context, _l10n(context).hermesProfileSaved);
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(
          context,
          _l10n(context).hermesProfileSaveFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _saveModel() async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    final provider = _provider.text.trim();
    final model = _model.text.trim();
    if (provider.isEmpty || model.isEmpty) {
      UiUtils.showMessage(
        context,
        _l10n(context).hermesProfileSaveFailed,
        isError: true,
      );
      return;
    }
    setState(() => _savingModel = true);
    try {
      await service.setProfileModel(
        name: widget.name,
        provider: provider,
        model: model,
      );
      ref.invalidate(hermesProfileListProvider);
      if (!mounted) return;
      UiUtils.showMessage(context, _l10n(context).hermesProfileSaved);
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(
          context,
          _l10n(context).hermesProfileSaveFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _savingModel = false);
    }
  }

  Future<void> _setActive() async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _settingActive = true);
    try {
      await service.setActiveProfile(widget.name);
      ref.invalidate(hermesActiveProfileProvider);
      if (!mounted) return;
      UiUtils.showMessage(context, _l10n(context).hermesProfileSaved);
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(
          context,
          _l10n(context).hermesProfileSaveFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _settingActive = false);
    }
  }
}
