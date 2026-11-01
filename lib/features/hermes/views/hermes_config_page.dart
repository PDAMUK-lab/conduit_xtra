import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_config_view.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/navigation/routes.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Read-only view of the server's config.yaml and environment keys.
///
/// The write path (PUT /api/config/raw) replaces the whole document, so it is
/// deliberately not in this slice: this page answers "what is configured"
/// without being able to damage it.
class HermesConfigPage extends ConsumerStatefulWidget {
  const HermesConfigPage({super.key});

  @override
  ConsumerState<HermesConfigPage> createState() => _HermesConfigPageState();
}

class _HermesConfigPageState extends ConsumerState<HermesConfigPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _setOnly = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final configAsync = ref.watch(hermesRawConfigProvider);
    final envAsync = ref.watch(hermesEnvVarsProvider);

    return UtilityPageScaffold.settings(
      title: l10n.hermesConfigTitle,
      children: [
        Text(
          l10n.hermesConfigSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        configAsync.when(
          data: (config) {
            if (config == null) {
              return _message(theme, l10n.hermesConfigNoFile, theme.error);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  config.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.codeStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: ConduitButton(
                        key: const ValueKey<String>('hermes-config-edit'),
                        text: l10n.hermesConfigEditTitle,
                        isSecondary: true,
                        isCompact: true,
                        onPressed: () =>
                            context.push(Routes.hermesConfigEdit),
                      ),
                    ),
                    if (ref.watch(hermesConfigUndoProvider) != null) ...[
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: ConduitButton(
                          key: const ValueKey<String>('hermes-config-restore'),
                          text: l10n.hermesConfigRestore,
                          isSecondary: true,
                          isCompact: true,
                          onPressed: () => context.push(
                            Routes.hermesConfigEdit,
                            extra: ref.read(hermesConfigUndoProvider),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                Container(
                  padding: const EdgeInsets.all(Spacing.sm),
                  decoration: BoxDecoration(
                    color: theme.groupedSurface,
                    borderRadius: BorderRadius.circular(AppBorderRadius.card),
                  ),
                  child: SelectableText(
                    config.yaml,
                    style: AppTypography.codeStyle.copyWith(
                      color: theme.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesConfigLoadFailed, theme.error),
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          l10n.hermesEnvTitle,
          style: AppTypography.labelStyle.copyWith(
            color: theme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Row(
          children: [
            Expanded(
              child: ConduitInput(
                hint: l10n.hermesConfigSearch,
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              l10n.hermesConfigSetOnly,
              style: AppTypography.captionStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
            AdaptiveSwitch(
              value: _setOnly,
              onChanged: (value) => setState(() => _setOnly = value),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        envAsync.when(
          data: (vars) {
            final filtered = vars
                .where((v) => (!_setOnly || v.isSet) && v.matches(_query))
                .toList(growable: false);
            if (filtered.isEmpty) {
              return _message(
                theme,
                l10n.hermesConfigEmptyEnv,
                theme.textSecondary,
              );
            }
            return Column(
              children: [
                for (final env in filtered) ...[
                  _envRow(env, theme),
                  const SizedBox(height: Spacing.xs),
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesConfigLoadFailed, theme.error),
        ),
      ],
    );
  }

  Widget _envRow(HermesEnvVar env, ConduitThemeExtension theme) => Container(
    padding: const EdgeInsets.all(Spacing.md),
    decoration: BoxDecoration(
      color: theme.groupedSurface,
      borderRadius: BorderRadius.circular(AppBorderRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                env.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.codeStyle.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (env.isSet && env.redactedValue.isNotEmpty)
              Text(
                env.redactedValue,
                style: AppTypography.captionStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
          ],
        ),
        if (env.description.isNotEmpty) ...[
          const SizedBox(height: Spacing.xxs),
          Text(
            env.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.captionStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
        ],
      ],
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
}
