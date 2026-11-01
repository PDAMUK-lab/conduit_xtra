import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/haptic_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/platform_scroll_physics.dart';
import '../../../shared/widgets/conduit_loading.dart';
import '../../../shared/widgets/sidebar_layout_contract.dart';
import '../../navigation/providers/sidebar_tab_scroll_registry.dart';

import 'package:conduit_core/features/navigation/models/sidebar_navigation_model.dart';
import 'package:conduit_core/navigation/routes.dart';

import '../../navigation/widgets/chats_drawer.dart'
    show sidebarSectionDisclosureIcon;

import 'package:conduit_core/features/navigation/providers/drawer_section_notifiers.dart';

import 'package:conduit_core/features/hermes/models/hermes_bot.dart';
import 'package:conduit_core/features/hermes/models/hermes_session.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit_core/features/hermes/services/hermes_pending_decision_store.dart';

import 'hermes_bot_tile.dart';
import 'hermes_connection_switcher.dart';
import 'hermes_jobs_sheet.dart';
import 'hermes_session_tile.dart';

/// Sidebar tab listing the user's Hermes server-side conversations, with one
/// compact entry point for scheduled agents when the server exposes jobs.
class HermesSessionsTab extends ConsumerStatefulWidget {
  const HermesSessionsTab({super.key, this.showBottomNavigationBar = true});

  final bool showBottomNavigationBar;

  @override
  ConsumerState<HermesSessionsTab> createState() => _HermesSessionsTabState();
}

class _HermesSessionsTabState extends ConsumerState<HermesSessionsTab>
    with SidebarTabScrollRegistration<HermesSessionsTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  SidebarTabId get sidebarTabId => SidebarTabId.hermes;

  @override
  ScrollController get sidebarScrollController => _scrollController;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(hermesCapabilitiesProvider).asData?.value;
    final showJobs = caps?.jobs ?? true;
    final sessionsAsync = ref.watch(hermesSessionsProvider);

    // The sidebar tab host has no Material ancestor; provide a transparent one
    // so InkWell / IconButton / CustomizationTile work inside this tab.
    // Top/bottom insets + the refresh edge offset mirror the Chats tab so the
    // content clears the native sidebar chrome and bottom tab bar.
    final scroll = CustomScrollView(
      controller: _scrollController,
      primary: false,
      physics: platformAlwaysScrollablePhysics(context),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(height: sidebarTabContentTopPadding(context)),
        ),
        // Names the active connection; switches when several are saved.
        const SliverToBoxAdapter(child: HermesConnectionSwitcherTile()),
        const SliverToBoxAdapter(child: _ApprovalsTile()),
        ..._botSlivers(context, ref.watch(hermesBotsProvider).asData?.value),
        if (showJobs) const SliverToBoxAdapter(child: _ScheduledAgentsTile()),
        if (ref.watch(hermesApiServiceProvider) is HermesDesktopApiService) ...[
          const SliverToBoxAdapter(child: _SkillsTile()),
          const SliverToBoxAdapter(child: _MemoryTile()),
          const SliverToBoxAdapter(child: _FilesTile()),
          const SliverToBoxAdapter(child: _ToolsetsTile()),
          const SliverToBoxAdapter(child: _ProfilesTile()),
          const SliverToBoxAdapter(child: _AnalyticsTile()),
          const SliverToBoxAdapter(child: _LogsTile()),
          const SliverToBoxAdapter(child: _ConfigTile()),
        ],
        ..._sessionSlivers(context, sessionsAsync),
        SliverToBoxAdapter(
          child: SizedBox(
            height: sidebarTabContentBottomPadding(
              context,
              includeNativeBottomBar: widget.showBottomNavigationBar,
            ),
          ),
        ),
      ],
    );
    final refreshable = ConduitRefreshIndicator(
      edgeOffset: sidebarRefreshIndicatorEdgeOffset(context),
      onRefresh: () async {
        if (showJobs) ref.invalidate(hermesJobsProvider);
        ref.invalidate(hermesBotsProvider);
        ref.invalidate(hermesSessionsProvider);
        await ref.read(hermesSessionsProvider.future);
      },
      child: scroll,
    );
    final primary = PrimaryScrollController(
      controller: _scrollController,
      child: refreshable,
    );
    return Material(
      type: MaterialType.transparency,
      child: context.usesCupertinoChrome
          ? CupertinoScrollbar(controller: _scrollController, child: primary)
          : Scrollbar(controller: _scrollController, child: primary),
    );
  }

  /// The Bot Mode roster, above everything else. Absent entirely on gateways
  /// without Bot Mode, which report no bots.
  List<Widget> _botSlivers(BuildContext context, List<HermesBot>? bots) {
    if (bots == null || bots.isEmpty) return const [];
    final expanded = ref.watch(hermesShowBotsProvider);
    return [
      SliverToBoxAdapter(
        child: _SectionHeader(
          title: AppLocalizations.of(context)!.hermesBotsTitle,
          count: bots.length,
          expanded: expanded,
          onToggle: () {
            ConduitHaptics.selectionClick();
            ref.read(hermesShowBotsProvider.notifier).toggle();
          },
        ),
      ),
      if (expanded)
        SliverPadding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          sliver: SliverList.builder(
            itemCount: bots.length,
            itemBuilder: (context, index) => HermesBotTile(bot: bots[index]),
          ),
        ),
    ];
  }

  List<Widget> _sessionSlivers(
    BuildContext context,
    AsyncValue<List<HermesSessionSummary>> sessionsAsync,
  ) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    return sessionsAsync.when(
      data: (sessions) {
        if (sessions.isEmpty) {
          return [
            SliverToBoxAdapter(
              child: _message(
                theme,
                Icons.smart_toy_outlined,
                l10n.hermesNoConversationsMessage,
                theme.textSecondary,
              ),
            ),
          ];
        }
        return [
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: l10n.hermesConversationsTitle,
              count: sessions.length,
            ),
          ),
          SliverPadding(
            // The shared conversation tile supplies the 4.0.3 Hermes 8pt row
            // gutter. Keep list padding vertical to avoid doubling that inset
            // only in this tab.
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            sliver: SliverList.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) =>
                  HermesSessionTile(session: sessions[index]),
            ),
          ),
        ];
      },
      loading: () => const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 64),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
      error: (_, _) => [
        SliverToBoxAdapter(
          child: _message(
            theme,
            Icons.error_outline,
            l10n.hermesConversationsLoadError,
            theme.error,
          ),
        ),
      ],
    );
  }

  Widget _message(
    ConduitThemeExtension theme,
    IconData icon,
    String text,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 80, left: 24, right: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: Spacing.md),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmallStyle.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ScheduledAgentsTile extends ConsumerWidget {
  const _ScheduledAgentsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(hermesJobsProvider);
    final jobs = jobsAsync.value;
    final count = jobs?.length;
    final activeCount = jobs?.where((job) => job.enabled).length;
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    final subtitle = switch ((count, activeCount, jobsAsync)) {
      (null, _, AsyncLoading()) => l10n.hermesSchedulesLoading,
      (null, _, AsyncError()) => l10n.hermesSchedulesUnavailable,
      (0, _, _) => l10n.hermesNoSchedulesYet,
      (final int total, final int active, _) => l10n.hermesSchedulesSummary(
        active,
        total,
      ),
      _ => l10n.hermesReviewSchedules,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-scheduled-agents-tile'),
        onTap: () => showHermesJobsSheet(context),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: IconSize.xl,
                height: IconSize.xl,
                child: Icon(
                  Icons.event_repeat_rounded,
                  size: IconSize.medium,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesScheduledAgentsTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: Spacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppBorderRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    style: AppTypography.labelMediumStyle.copyWith(
                      color: theme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Approvals waiting across every conversation of this connection.
///
/// Hidden entirely when nothing is waiting: an empty inbox is not a place, it
/// is the absence of one. The count is the same store the inbox page reads, so
/// answering a decision anywhere makes this row disappear.
class _ApprovalsTile extends ConsumerWidget {
  const _ApprovalsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending =
        ref.watch(hermesPendingDecisionsProvider).asData?.value ??
        const <HermesPendingDesktopDecision>[];
    if (pending.isEmpty) return const SizedBox.shrink();
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    final firstPrompt = pending.first.prompt?.trim();
    final subtitle = firstPrompt == null || firstPrompt.isEmpty
        ? l10n.hermesApprovalsSubtitle
        : firstPrompt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-approvals-tile'),
        onTap: () => context.push(Routes.hermesApprovals),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: IconSize.xl,
                height: IconSize.xl,
                child: Icon(
                  Icons.verified_user_outlined,
                  size: IconSize.medium,
                  color: theme.buttonPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesApprovalsTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm,
                  vertical: Spacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: theme.buttonPrimary.withValues(alpha: Alpha.badgeBackground),
                  borderRadius: BorderRadius.circular(AppBorderRadius.pill),
                ),
                child: Text(
                  '${pending.length}',
                  style: AppTypography.labelMediumStyle.copyWith(
                    color: theme.buttonPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillsTile extends ConsumerWidget {
  const _SkillsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(hermesDashboardSkillsProvider).asData?.value;
    final enabled = skills?.where((skill) => skill.enabled).length;
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    final subtitle = skills == null || enabled == null
        ? l10n.hermesSkillsSubtitle
        : '$enabled/${skills.length}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-skills-tile'),
        onTap: () => context.push(Routes.hermesSkills),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: IconSize.xl,
                height: IconSize.xl,
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: IconSize.medium,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesSkillsTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigTile extends ConsumerWidget {
  const _ConfigTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-config-tile'),
        onTap: () => context.push(Routes.hermesConfig),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: IconSize.xl,
                height: IconSize.xl,
                child: Icon(
                  Icons.tune_outlined,
                  size: IconSize.medium,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesConfigTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      l10n.hermesConfigSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsTile extends ConsumerWidget {
  const _AnalyticsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-analytics-tile'),
        onTap: () => context.push(Routes.hermesAnalytics),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: IconSize.xl,
                height: IconSize.xl,
                child: Icon(
                  Icons.insights_outlined,
                  size: IconSize.medium,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesAnalyticsTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      l10n.hermesAnalyticsSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogsTile extends ConsumerWidget {
  const _LogsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-logs-tile'),
        onTap: () => context.push(Routes.hermesLogs),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: IconSize.xl,
                height: IconSize.xl,
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: IconSize.medium,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesLogsTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      l10n.hermesLogsSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilesTile extends ConsumerWidget {
  const _ProfilesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-profiles-tile'),
        onTap: () => context.push(Routes.hermesProfiles),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: IconSize.xl,
                height: IconSize.xl,
                child: Icon(
                  Icons.people_outline,
                  size: IconSize.medium,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesProfilesTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      l10n.hermesProfilesSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolsetsTile extends ConsumerWidget {
  const _ToolsetsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-toolsets-tile'),
        onTap: () => context.push(Routes.hermesToolsets),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: IconSize.xl,
                height: IconSize.xl,
                child: Icon(
                  Icons.handyman_outlined,
                  size: IconSize.medium,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesToolsetsTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      l10n.hermesToolsetsSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilesTile extends ConsumerWidget {
  const _FilesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-files-tile'),
        onTap: () => context.push(Routes.hermesFiles),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: IconSize.xl,
                height: IconSize.xl,
                child: Icon(
                  Icons.folder_open_outlined,
                  size: IconSize.medium,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesFilesTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      l10n.hermesFilesSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryTile extends ConsumerWidget {
  const _MemoryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    final subtitle = l10n.hermesWikiSubtitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-memory-tile'),
        onTap: () => context.push(Routes.hermesMemory),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: IconSize.xl,
                height: IconSize.xl,
                child: Icon(
                  Icons.memory_outlined,
                  size: IconSize.medium,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesWikiTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section header with an optional count badge.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.count,
    this.expanded,
    this.onToggle,
  });

  final String title;
  final int? count;

  /// Disclosure state; null renders a plain, non-collapsible header.
  final bool? expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final titleStyle = AppTypography.labelStyle.copyWith(
      color: theme.textSecondary,
      fontWeight: FontWeight.w700,
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (expanded != null) ...[
                  Icon(
                    sidebarSectionDisclosureIcon(expanded!),
                    color: theme.iconSecondary,
                    size: IconSize.listItem,
                  ),
                  const SizedBox(width: Spacing.xxs),
                ],
                Text(title, style: titleStyle),
                if (count != null) ...[
                  const SizedBox(width: Spacing.sm),
                  Text(
                    '$count',
                    style: AppTypography.labelMediumStyle.copyWith(
                      color: theme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onToggle == null) return header;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: header,
    );
  }
}
