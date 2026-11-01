import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:conduit_core/features/hermes/models/hermes_live_activity.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';

/// The step the running turn is on, shown under the typing indicator.
///
/// The gateway streams `thinking.delta`, `message.delta` and tool frames to
/// every viewer; without this line an app watching another client's turn shows
/// a spinner that never moves, which reads as a hang (and invites a Stop that
/// kills someone else's work).
class HermesLiveActivityLine extends ConsumerWidget {
  const HermesLiveActivityLine({
    super.key,
    required this.storedSessionId,
    this.maxCharacters = 120,
  });

  final String storedSessionId;
  final int maxCharacters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref
        .watch(hermesLiveActivityProvider(storedSessionId))
        .asData
        ?.value;
    if (activity == null || activity.kind == HermesLiveActivityKind.done) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final failed = activity.failed;
    final color = failed ? theme.colorScheme.error : secondary;
    final label = _label(activity);
    final detail = _trim(activity.detail, maxCharacters);
    final body = detail.isEmpty ? label : '$label · $detail';
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 2, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(activity.kind, failed), size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  static String _label(HermesLiveActivity activity) {
    switch (activity.kind) {
      case HermesLiveActivityKind.thinking:
        return activity.text.isEmpty ? 'Thinking…' : _trim(activity.text, 120);
      case HermesLiveActivityKind.writing:
        return activity.text.isEmpty ? 'Writing…' : _trim(activity.text, 120);
      case HermesLiveActivityKind.tool:
        return activity.text;
      case HermesLiveActivityKind.subagent:
        return activity.text;
      case HermesLiveActivityKind.done:
        return '';
    }
  }

  static IconData _icon(HermesLiveActivityKind kind, bool failed) {
    if (failed) return Icons.error_outline;
    switch (kind) {
      case HermesLiveActivityKind.thinking:
        return Icons.psychology_outlined;
      case HermesLiveActivityKind.writing:
        return Icons.edit_note;
      case HermesLiveActivityKind.tool:
        return Icons.build_outlined;
      case HermesLiveActivityKind.subagent:
        return Icons.hub_outlined;
      case HermesLiveActivityKind.done:
        return Icons.check;
    }
  }

  static String _trim(String value, int limit) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= limit) return collapsed;
    return '…${collapsed.substring(collapsed.length - limit)}';
  }
}
