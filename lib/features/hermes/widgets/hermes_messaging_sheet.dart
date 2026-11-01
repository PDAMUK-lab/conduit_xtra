import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/themed_sheets.dart';

import 'package:conduit_core/features/hermes/models/hermes_messaging.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

Future<void> showHermesMessagingSheet(
  BuildContext context,
  HermesMessagingPlatform platform,
) => ThemedSheets.showSurface(
  context: context,
  padding: EdgeInsets.zero,
  builder: (_) => HermesMessagingSheet(platform: platform),
);

/// One channel: what it needs, what state it is in, and a check action.
///
/// Credential values are never displayed — only whether each required key is
/// set. Enabling a channel is done from the list, not here.
class HermesMessagingSheet extends ConsumerStatefulWidget {
  const HermesMessagingSheet({super.key, required this.platform});

  final HermesMessagingPlatform platform;

  @override
  ConsumerState<HermesMessagingSheet> createState() =>
      _HermesMessagingSheetState();
}

class _HermesMessagingSheetState extends ConsumerState<HermesMessagingSheet> {
  bool _testing = false;
  String? _result;
  bool _ok = true;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final platform = widget.platform;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.66,
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
              platform.name,
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
              platform.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.captionStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                if (platform.errorMessage != null &&
                    platform.errorMessage!.isNotEmpty) ...[
                  Text(
                    platform.errorMessage!,
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.error,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
                if (platform.homeChannel != null &&
                    platform.homeChannel!.isNotEmpty) ...[
                  Text(
                    l10n.hermesMessagingHomeChannel(platform.homeChannel!),
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
                Text(
                  l10n.hermesMessagingSetup,
                  style: AppTypography.labelStyle.copyWith(
                    color: theme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                for (final env in platform.envVars) ...[
                  Row(
                    children: [
                      Icon(
                        env.isSet ? Icons.check_circle : Icons.cancel_outlined,
                        size: IconSize.small,
                        color: env.isSet ? theme.success : theme.textSecondary,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text(
                          env.key,
                          style: AppTypography.codeStyle.copyWith(
                            color: theme.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (env.required)
                        Text(
                          l10n.hermesMessagingRequired,
                          style: AppTypography.captionStyle.copyWith(
                            color: theme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  if (env.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: Spacing.lg,
                        bottom: Spacing.xs,
                      ),
                      child: Text(
                        env.description,
                        style: AppTypography.captionStyle.copyWith(
                          color: theme.textSecondary,
                        ),
                      ),
                    ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: Spacing.md),
                  Text(
                    _result!,
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: _ok ? theme.textPrimary : theme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (platform.enabled) Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: ConduitButton(
              key: const ValueKey<String>('hermes-messaging-test'),
              text: _testing
                  ? l10n.hermesMessagingTesting
                  : l10n.hermesMessagingTest,
              isSecondary: true,
              isFullWidth: true,
              isLoading: _testing,
              onPressed: _testing ? null : _test,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _test() async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    final l10n = _l10n(context);
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final result = await service.testMessagingPlatform(widget.platform.id);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _ok = result?.ok ?? false;
        _result = result?.message.isNotEmpty == true
            ? result!.message
            : l10n.hermesMessagingTestDone;
      });
      ref.invalidate(hermesMessagingProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _ok = false;
        _result = RegExp(r'"detail"\s*:\s*"([^"]{1,300})"')
                .firstMatch(error.toString())
                ?.group(1) ??
            l10n.hermesMessagingTestFailed;
      });
    }
  }
}
