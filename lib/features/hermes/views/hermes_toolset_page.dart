import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_toolsets.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// One toolset: which provider it runs on, which model it uses, and which of
/// the provider's environment keys are already set.
///
/// Environment values are never shown or edited here — only whether each key
/// is set. Secrets belong on the server, and a phone keyboard is the wrong
/// place to paste them.
class HermesToolsetPage extends ConsumerStatefulWidget {
  const HermesToolsetPage({super.key, required this.name});

  final String name;

  @override
  ConsumerState<HermesToolsetPage> createState() => _HermesToolsetPageState();
}

class _HermesToolsetPageState extends ConsumerState<HermesToolsetPage> {
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final configAsync = ref.watch(hermesToolsetConfigProvider(widget.name));
    final modelsAsync = ref.watch(hermesToolsetModelsProvider(widget.name));

    return UtilityPageScaffold.settings(
      title: widget.name,
      children: [
        configAsync.when(
          data: (config) {
            if (config == null) {
              return _message(theme, l10n.hermesToolsetsLoadFailed, theme.error);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (config.providers.isNotEmpty) ...[
                  _sectionTitle(l10n.hermesToolsetProviders, theme),
                  for (final provider in config.providers) ...[
                    _providerRow(provider, config, theme, l10n),
                    const SizedBox(height: Spacing.xs),
                  ],
                  const SizedBox(height: Spacing.md),
                ],
                modelsAsync.when(
                  data: (models) {
                    if (models == null || models.models.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle(l10n.hermesToolsetModels, theme),
                        for (final model in models.models) ...[
                          _modelRow(model, models, theme, l10n),
                          const SizedBox(height: Spacing.xs),
                        ],
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesToolsetsLoadFailed, theme.error),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text, ConduitThemeExtension theme) => Padding(
    padding: const EdgeInsets.only(bottom: Spacing.xs),
    child: Text(
      text,
      style: AppTypography.labelStyle.copyWith(
        color: theme.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _card(ConduitThemeExtension theme, Widget child) => Container(
    padding: const EdgeInsets.all(Spacing.md),
    decoration: BoxDecoration(
      color: theme.groupedSurface,
      borderRadius: BorderRadius.circular(AppBorderRadius.card),
    ),
    child: child,
  );

  Widget _providerRow(
    HermesToolsetProvider provider,
    HermesToolsetConfig config,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    final busy = _busy == 'provider:${provider.name}';
    final active = provider.isActive || provider.name == config.activeProvider;
    return _card(
      theme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  provider.name,
                  style: AppTypography.standard.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (active)
                Text(
                  l10n.hermesToolsetCurrent,
                  style: AppTypography.captionStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                )
              else if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                ConduitButton(
                  key: ValueKey<String>(
                    'hermes-toolset-provider-${provider.name}',
                  ),
                  text: l10n.hermesToolsetUse,
                  isSecondary: true,
                  isCompact: true,
                  onPressed: _busy == null
                      ? () => _useProvider(provider.name)
                      : null,
                ),
            ],
          ),
          if (provider.status.isNotEmpty) ...[
            const SizedBox(height: Spacing.xxs),
            Text(
              provider.status,
              style: AppTypography.captionStyle.copyWith(
                color: provider.status == 'ready'
                    ? theme.textSecondary
                    : theme.error,
              ),
            ),
          ],
          if (provider.envVars.isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xxs,
              children: [
                for (final env in provider.envVars)
                  Text(
                    '${env.key} ${env.isSet ? l10n.hermesToolsetEnvSet : l10n.hermesToolsetEnvMissing}',
                    style: AppTypography.captionStyle.copyWith(
                      color: env.isSet ? theme.textSecondary : theme.error,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _modelRow(
    HermesToolsetModel model,
    HermesToolsetModels models,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    final busy = _busy == 'model:${model.id}';
    final current = model.id == models.current;
    return _card(
      theme,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.standard.copyWith(
                    color: theme.textPrimary,
                  ),
                ),
                if (model.price.isNotEmpty || model.speed.isNotEmpty) ...[
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    [model.price, model.speed]
                        .where((part) => part.isNotEmpty)
                        .join(' · '),
                    style: AppTypography.captionStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          if (current)
            Text(
              l10n.hermesToolsetCurrent,
              style: AppTypography.captionStyle.copyWith(
                color: theme.textSecondary,
              ),
            )
          else if (busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            ConduitButton(
              key: ValueKey<String>('hermes-toolset-model-${model.id}'),
              text: l10n.hermesToolsetUse,
              isSecondary: true,
              isCompact: true,
              onPressed: _busy == null ? () => _useModel(model.id) : null,
            ),
        ],
      ),
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

  Future<void> _useProvider(String provider) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _busy = 'provider:$provider');
    try {
      await service.setToolsetProvider(name: widget.name, provider: provider);
      ref.invalidate(hermesToolsetConfigProvider(widget.name));
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(
          context,
          _l10n(context).hermesToolsetSelectFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _useModel(String model) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _busy = 'model:$model');
    try {
      await service.setToolsetModel(name: widget.name, model: model);
      ref.invalidate(hermesToolsetModelsProvider(widget.name));
      ref.invalidate(hermesToolsetConfigProvider(widget.name));
    } catch (_) {
      if (mounted) {
        UiUtils.showMessage(
          context,
          _l10n(context).hermesToolsetSelectFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}
