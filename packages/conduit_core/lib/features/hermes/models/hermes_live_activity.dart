import 'package:meta/meta.dart';

/// One visible step of a turn another client is running.
///
/// The gateway already sends `thinking.delta`, `message.delta`, `tool.start`,
/// `tool.progress` and `tool.complete` to every viewer, but the app only
/// reloaded the transcript when the turn ended — so a long tool-using turn
/// looked like a spinner that never moved, and the operator stopped it.
@immutable
final class HermesLiveActivity {
  const HermesLiveActivity({
    required this.kind,
    required this.text,
    this.detail = '',
    this.failed = false,
  });

  final HermesLiveActivityKind kind;

  /// What to show: the tool's name, or the tail of the thinking/writing text.
  final String text;

  /// Extra context for a tool step (its argument preview or result), bounded.
  final String detail;

  /// A tool that reported an error.
  final bool failed;

  HermesLiveActivity copyWith({String? text, String? detail, bool? failed}) =>
      HermesLiveActivity(
        kind: kind,
        text: text ?? this.text,
        detail: detail ?? this.detail,
        failed: failed ?? this.failed,
      );

  @override
  String toString() => 'HermesLiveActivity($kind, $text)';
}

enum HermesLiveActivityKind { thinking, writing, tool, subagent, done }
