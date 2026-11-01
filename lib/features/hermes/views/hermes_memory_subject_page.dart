import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

String _when(double epoch) {
  if (epoch <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(
    (epoch * 1000).round(),
  ).toLocal();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.year}-$month-$day $hour:$minute';
}

/// One subject's page: what the wiki aggregated from session history.
class HermesMemorySubjectPage extends ConsumerWidget {
  const HermesMemorySubjectPage({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final subjectAsync = ref.watch(hermesMemoryWikiSubjectProvider(slug));

    return UtilityPageScaffold.settings(
      title: slug,
      children: [
        subjectAsync.when(
          data: (subject) {
            if (subject == null) {
              return _message(theme, l10n.hermesWikiLoadFailed, theme.error);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  subject.name,
                  style: AppTypography.titleMediumStyle.copyWith(
                    color: theme.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.xxs),
                Text(
                  '${l10n.hermesWikiSessions(subject.sessionCount)} · '
                  '${l10n.hermesWikiMessages(subject.messageCount)}',
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
                if (subject.keywords.isNotEmpty) ...[
                  const SizedBox(height: Spacing.sm),
                  Text(
                    l10n.hermesWikiKeywords,
                    style: AppTypography.labelStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Spacing.xxs),
                  Wrap(
                    spacing: Spacing.xs,
                    runSpacing: Spacing.xxs,
                    children: [
                      for (final keyword in subject.keywords)
                        ConduitBadge(text: keyword, isCompact: true),
                    ],
                  ),
                ],
                if (subject.snippets.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  Text(
                    l10n.hermesWikiMentions,
                    style: AppTypography.labelStyle.copyWith(
                      color: theme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final snippet in subject.snippets) ...[
                    const SizedBox(height: Spacing.xs),
                    _card(
                      theme,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (snippet.role != null)
                            Text(
                              snippet.role!,
                              style: AppTypography.captionStyle.copyWith(
                                color: theme.textSecondary,
                              ),
                            ),
                          const SizedBox(height: Spacing.xxs),
                          Text(
                            snippet.text,
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmallStyle.copyWith(
                              color: theme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                if (subject.sessions.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  Text(
                    l10n.hermesWikiSessions(subject.sessionCount),
                    style: AppTypography.labelStyle.copyWith(
                      color: theme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final session in subject.sessions) ...[
                    const SizedBox(height: Spacing.xs),
                    _card(
                      theme,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.title?.isNotEmpty == true
                                ? session.title!
                                : session.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.standard.copyWith(
                              color: theme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: Spacing.xxs),
                          Text(
                            [
                              if (session.source != null) session.source!,
                              _when(session.lastActive),
                            ].where((part) => part.isNotEmpty).join(' · '),
                            style: AppTypography.captionStyle.copyWith(
                              color: theme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              _message(theme, l10n.hermesWikiLoadFailed, theme.error),
        ),
      ],
    );
  }

  Widget _card(ConduitThemeExtension theme, Widget child) => Container(
    padding: const EdgeInsets.all(Spacing.md),
    decoration: BoxDecoration(
      color: theme.groupedSurface,
      borderRadius: BorderRadius.circular(AppBorderRadius.card),
    ),
    child: child,
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
