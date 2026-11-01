import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_session.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';

import '../widgets/hermes_session_tile.dart' show openHermesSession;

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Full-text search across stored sessions (`/api/sessions/search`).
class HermesSessionSearchPage extends ConsumerStatefulWidget {
  const HermesSessionSearchPage({super.key});

  @override
  ConsumerState<HermesSessionSearchPage> createState() =>
      _HermesSessionSearchPageState();
}

class _HermesSessionSearchPageState
    extends ConsumerState<HermesSessionSearchPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _submitted = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final query = _submitted.trim();
    final results = query.length >= 2
        ? ref.watch(hermesSessionSearchProvider(query))
        : null;

    return UtilityPageScaffold.settings(
      title: l10n.hermesSessionSearchTitle,
      children: [
        ConduitInput(
          hint: l10n.hermesSessionSearchHint,
          controller: _query,
          autofocus: true,
          onChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () {
              if (mounted) setState(() => _submitted = value);
            });
          },
        ),
        const SizedBox(height: Spacing.md),
        if (results == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(
              child: Text(
                l10n.hermesSessionSearchPrompt,
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ),
          )
        else
          results.when(
            data: (hits) {
              if (hits.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                  child: Center(
                    child: Text(
                      l10n.hermesSessionSearchEmpty,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final hit in hits) ...[
                    _result(hit, theme),
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
                  l10n.hermesSessionSearchFailed,
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: theme.error,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _result(HermesSessionSummary hit, ConduitThemeExtension theme) {
    final preview = hit.preview?.trim() ?? '';
    return Container(
      key: ValueKey<String>('hermes-search-${hit.id}'),
      decoration: BoxDecoration(
        color: theme.groupedSurface,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        onTap: () => openHermesSession(context, ref, hit),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hit.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMediumStyle.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: Spacing.xxs),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
