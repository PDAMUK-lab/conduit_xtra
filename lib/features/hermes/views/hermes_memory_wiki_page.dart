import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';

import 'package:conduit_core/features/hermes/models/hermes_memory_wiki.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/navigation/routes.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// The Memory Wiki: what the agent remembers, derived from local session
/// history by the dashboard's memory-wiki plugin — subjects, daily logs, the
/// persistent MEMORY.md/USER.md entries, and the active provider's archive.
///
/// Read-only. Provider choice lives behind the settings action, because the
/// question a phone user asks here is "what does it remember", not "which
/// backend stores it".
class HermesMemoryWikiPage extends ConsumerStatefulWidget {
  const HermesMemoryWikiPage({super.key});

  @override
  ConsumerState<HermesMemoryWikiPage> createState() =>
      _HermesMemoryWikiPageState();
}

class _HermesMemoryWikiPageState extends ConsumerState<HermesMemoryWikiPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = context.conduitTheme;
    final overviewAsync = ref.watch(hermesMemoryWikiOverviewProvider);
    final archiveAsync = ref.watch(hermesMemoryWikiArchiveProvider);

    return UtilityPageScaffold.settings(
      title: l10n.hermesWikiTitle,
      trailing: IconButton(
        key: const ValueKey<String>('hermes-wiki-settings'),
        icon: const Icon(Icons.settings_outlined),
        tooltip: l10n.hermesWikiSettings,
        onPressed: () => context.push(Routes.hermesMemorySettings),
      ),
      children: [
        Text(
          l10n.hermesWikiSubtitle,
          style: AppTypography.bodySmallStyle.copyWith(
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        overviewAsync.when(
          data: (overview) {
            if (overview == null) {
              return _message(theme, l10n.hermesWikiLoadFailed, theme.error);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _notesSection(overview.notes, theme, l10n),
                const SizedBox(height: Spacing.lg),
                _subjectsSection(overview.subjects, theme, l10n),
                const SizedBox(height: Spacing.lg),
                _daysSection(overview.days, theme, l10n),
                const SizedBox(height: Spacing.lg),
                archiveAsync.when(
                  data: (archive) => _archiveSection(archive, theme, l10n),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => _archiveSection(null, theme, l10n),
                ),
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

  Widget _card({required Widget child, required ConduitThemeExtension theme}) =>
      Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: theme.groupedSurface,
          borderRadius: BorderRadius.circular(AppBorderRadius.card),
        ),
        child: child,
      );

  Widget _notesSection(
    HermesWikiNotes notes,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    if (notes.memoryCount == 0 && notes.userCount == 0) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.hermesWikiPersistent, theme),
        _card(
          theme: theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MEMORY.md · ${l10n.hermesWikiEntries(notes.memoryCount)}',
                style: AppTypography.standard.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final entry in notes.memory.take(4)) ...[
                const SizedBox(height: Spacing.xxs),
                Text(
                  entry,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              ],
              if (notes.memory.length > 4) ...[
                const SizedBox(height: Spacing.xxs),
                Text(
                  '…',
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.sm),
              Text(
                'USER.md · ${l10n.hermesWikiEntries(notes.userCount)}',
                style: AppTypography.standard.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final entry in notes.user.take(3)) ...[
                const SizedBox(height: Spacing.xxs),
                Text(
                  entry,
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
      ],
    );
  }

  Widget _subjectsSection(
    List<HermesWikiSubject> subjects,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) {
    final filtered = subjects.where((subject) => subject.matches(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.hermesWikiSubjects, theme),
        ConduitInput(
          hint: l10n.hermesWikiSearchSubjects,
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: Spacing.sm),
        if (filtered.isEmpty)
          _card(
            theme: theme,
            child: Text(
              l10n.hermesWikiNoSubjects,
              style: AppTypography.bodySmallStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          )
        else
          for (final subject in filtered.take(50)) ...[
            _card(
              theme: theme,
              child: InkWell(
                key: ValueKey<String>('hermes-wiki-subject-${subject.slug}'),
                onTap: () => context.push(
                  Routes.hermesMemorySubjectPath(subject.slug),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.standard.copyWith(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.w600,
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
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: IconSize.listItem,
                      color: theme.iconSecondary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
          ],
      ],
    );
  }

  Widget _daysSection(
    List<HermesWikiDay> days,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionTitle(l10n.hermesWikiDays, theme),
      if (days.isEmpty)
        _card(
          theme: theme,
          child: Text(
            l10n.hermesWikiNoDays,
            style: AppTypography.bodySmallStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
        )
      else
        for (final day in days.take(14)) ...[
          _card(
            theme: theme,
            child: InkWell(
              key: ValueKey<String>('hermes-wiki-day-${day.date}'),
              onTap: () =>
                  context.push(Routes.hermesMemoryDayPath(day.date)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          day.date,
                          style: AppTypography.standard.copyWith(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Spacing.xxs),
                        Text(
                          '${l10n.hermesWikiSessions(day.sessionCount)} · '
                          '${l10n.hermesWikiMessages(day.messageCount)}',
                          style: AppTypography.bodySmallStyle.copyWith(
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: IconSize.listItem,
                    color: theme.iconSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
        ],
    ],
  );

  Widget _archiveSection(
    HermesMemoryArchive? archive,
    ConduitThemeExtension theme,
    AppLocalizations l10n,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionTitle(l10n.hermesWikiArchive, theme),
      _card(
        theme: theme,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              archive == null || !archive.available
                  ? l10n.hermesWikiArchiveUnavailable
                  : '${archive.provider} · ${l10n.hermesWikiEntries(archive.total)}',
              style: AppTypography.standard.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (archive != null && archive.available) ...[
              const SizedBox(height: Spacing.xxs),
              Text(
                'active ${archive.active} · archived ${archive.archived} · '
                'notes ${archive.notes} · pins ${archive.pins}',
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
              for (final entry in archive.entries.take(10)) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  '${entry.status}${entry.target == null ? '' : ' · ${entry.target}'}',
                  style: AppTypography.captionStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.xxs),
                Text(
                  entry.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: theme.textPrimary,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    ],
  );
}
