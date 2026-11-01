import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_skill.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit_core/navigation/routes.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// The agent's installed skills: enable/disable, open one to edit its
/// SKILL.md, or start a new one.
///
/// Reads the dashboard's `GET /api/skills`, which is the only Hermes surface
/// that reports the enabled flag and category; the chat-facing RPC list does
/// not, so editing from a phone needs this page rather than the prompt list.
class HermesSkillsPage extends ConsumerStatefulWidget {
  const HermesSkillsPage({super.key});

  @override
  ConsumerState<HermesSkillsPage> createState() => _HermesSkillsPageState();
}

class _HermesSkillsPageState extends ConsumerState<HermesSkillsPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _busyName;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final skillsAsync = ref.watch(hermesDashboardSkillsProvider);
    final service = ref.watch(hermesApiServiceProvider);
    final writable = service is HermesDesktopApiService;

    return UtilityPageScaffold.settings(
      title: l10n.hermesSkillsTitle,
      onRefresh: () async {
        ref.invalidate(hermesDashboardSkillsProvider);
      },
      children: [
        ConduitButton(
          key: const ValueKey<String>('hermes-skill-new'),
          text: l10n.hermesSkillsNew,
          icon: Icons.add,
          isFullWidth: true,
          onPressed: writable
              ? () => context.push(Routes.hermesSkillEditor)
              : null,
        ),
        const SizedBox(height: Spacing.md),
        ConduitInput(
          hint: l10n.hermesSkillsSearchHint,
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: IconSize.small),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
        ),
        const SizedBox(height: Spacing.lg),
        skillsAsync.when(
          data: (skills) {
            final filtered = skills
                .where((skill) => skill.matches(_query))
                .toList(growable: false);
            if (skills.isEmpty) {
              return _message(theme, l10n.hermesSkillsEmpty, theme.textSecondary);
            }
            if (filtered.isEmpty) {
              return _message(
                theme,
                l10n.hermesSkillsNoMatch,
                theme.textSecondary,
              );
            }
            return Column(
              children: [
                for (final skill in filtered) ...[
                  _SkillTile(
                    key: ValueKey<String>('hermes-skill-${skill.name}'),
                    skill: skill,
                    busy: _busyName == skill.name,
                    writable: writable,
                    onOpen: () => context.push(
                      Routes.hermesSkillEditorPath(skill.name),
                    ),
                    onToggle: (enabled) => _toggle(skill, enabled),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesSkillsLoadFailed, theme.error),
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

  Future<void> _toggle(HermesSkill skill, bool enabled) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _busyName = skill.name);
    try {
      await service.setSkillEnabled(name: skill.name, enabled: enabled);
      ref.invalidate(hermesDashboardSkillsProvider);
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(
          context,
          _l10n(context).hermesSkillToggleFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyName = null);
    }
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({
    super.key,
    required this.skill,
    required this.busy,
    required this.writable,
    required this.onOpen,
    required this.onToggle,
  });

  final HermesSkill skill;
  final bool busy;
  final bool writable;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final category = skill.category;
    return InkWell(
      onTap: busy ? null : onOpen,
      borderRadius: BorderRadius.circular(AppBorderRadius.card),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: theme.groupedSurface,
          borderRadius: BorderRadius.circular(AppBorderRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.standard.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    skill.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                  if (category != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(
                      category,
                      style: AppTypography.captionStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(Spacing.sm),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              AdaptiveSwitch(
                value: skill.enabled,
                onChanged: writable ? onToggle : null,
              ),
          ],
        ),
      ),
    );
  }
}
