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

String _clock(double epoch) {
  if (epoch <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(
    (epoch * 1000).round(),
  ).toLocal();
  return '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

/// One day of the wiki: what was worked on, which sessions, which subjects.
class HermesMemoryDayPage extends ConsumerWidget {
  const HermesMemoryDayPage({super.key, required this.date});

  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final dayAsync = ref.watch(hermesMemoryWikiDayProvider(date));

    return UtilityPageScaffold.settings(
      title: date,
      children: [
        dayAsync.when(
          data: (day) {
            if (day == null) {
              return _message(theme, l10n.hermesWikiLoadFailed, theme.error);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${l10n.hermesWikiSessions(day.sessionCount)} · '
                  '${l10n.hermesWikiMessages(day.messageCount)}',
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
                if (day.subjects.isNotEmpty) ...[
                  const SizedBox(height: Spacing.sm),
                  Wrap(
                    spacing: Spacing.xs,
                    runSpacing: Spacing.xxs,
                    children: [
                      for (final subject in day.subjects.take(12))
                        ConduitBadge(
                          text: '${subject.name} ${subject.count}',
                          isCompact: true,
                        ),
                    ],
                  ),
                ],
                if (day.workItems.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  Text(
                    l10n.hermesWikiWork,
                    style: AppTypography.labelStyle.copyWith(
                      color: theme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final item in day.workItems) ...[
                    const SizedBox(height: Spacing.xs),
                    _card(
                      theme,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.kind} · ${_clock(item.timestamp)}',
                            style: AppTypography.captionStyle.copyWith(
                              color: theme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: Spacing.xxs),
                          Text(
                            item.text,
                            maxLines: 4,
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
                if (day.sessions.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  Text(
                    l10n.hermesWikiSessions(day.sessionCount),
                    style: AppTypography.labelStyle.copyWith(
                      color: theme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final session in day.sessions) ...[
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
                              if (session.preview != null)
                                session.preview!.length > 120
                                    ? '${session.preview!.substring(0, 120)}…'
                                    : session.preview!,
                            ].where((part) => part.isNotEmpty).join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
