import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_messaging.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

import '../widgets/hermes_messaging_sheet.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Messaging channels: what is on, what needs setup, and a per-channel check.
class HermesMessagingPage extends ConsumerStatefulWidget {
  const HermesMessagingPage({super.key});

  @override
  ConsumerState<HermesMessagingPage> createState() =>
      _HermesMessagingPageState();
}

class _HermesMessagingPageState extends ConsumerState<HermesMessagingPage> {
  String? _busyId;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final platforms = ref.watch(hermesMessagingProvider);

    return UtilityPageScaffold.settings(
      title: l10n.hermesMessagingTitle,
      onRefresh: () async {
        ref.invalidate(hermesMessagingProvider);
      },
      children: [
        Text(
          l10n.hermesMessagingSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        platforms.when(
          data: (rows) {
            if (rows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Center(
                  child: Text(
                    l10n.hermesMessagingEmpty,
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final platform in rows) ...[
                  _card(platform, theme, l10n),
                  const SizedBox(height: Spacing.xs),
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(
              child: Text(
                l10n.hermesMessagingLoadFailed,
                style: AppTypography.bodySmallStyle.copyWith(color: theme.error),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(
    HermesMessagingPlatform platform,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    final state = platform.enabled
        ? (platform.configured
              ? l10n.hermesMessagingEnabled
              : l10n.hermesMessagingNeedsSetup)
        : l10n.hermesMessagingDisabled;
    return Container(
      key: ValueKey<String>('hermes-messaging-${platform.id}'),
      decoration: BoxDecoration(
        color: theme.groupedSurface,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        onTap: () => showHermesMessagingSheet(context, platform),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      platform.name,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      state,
                      style: AppTypography.captionStyle.copyWith(
                        color: platform.enabled && !platform.configured
                            ? theme.error
                            : theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_busyId == platform.id)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                AdaptiveSwitch(
                  key: ValueKey<String>('hermes-messaging-toggle-${platform.id}'),
                  value: platform.enabled,
                  onChanged: (value) => _toggle(platform, value, l10n),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(
    HermesMessagingPlatform platform,
    bool enabled,
    AppLocalizations l10n,
  ) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() => _busyId = platform.id);
    try {
      await service.setMessagingPlatformEnabled(platform.id, enabled: enabled);
      ref.invalidate(hermesMessagingProvider);
      if (!mounted) return;
      UiUtils.showMessage(
        context,
        enabled ? l10n.hermesMessagingEnabledToast : l10n.hermesMessagingDisabledToast,
      );
    } catch (error) {
      if (!mounted) return;
      final detail = RegExp(r'"detail"\s*:\s*"([^"]{1,300})"')
          .firstMatch(error.toString())
          ?.group(1);
      UiUtils.showMessage(
        context,
        detail ?? l10n.hermesMessagingToggleFailed,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }
}
