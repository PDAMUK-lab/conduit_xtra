/// One hand-off point for alerts raised while the app is not in front.
///
/// The live runtime knows when a turn completes and whether the app is
/// foregrounded; the notification router lives in the app layer and cannot be
/// imported from this package. A static sink keeps the two apart without
/// depending on *which* service instance the app is holding — a stream on one
/// instance looked wired but never fired, because the UI and the provider held
/// different instances of the same service.
class HermesBackgroundAlerts {
  HermesBackgroundAlerts._();

  /// Set once at startup by the app layer. Null in tests and on hosts with no
  /// notification surface, where a missing alert is correct rather than an error.
  static void Function(String storedId)? onReplyReady;

  static void replyReady(String storedId) => onReplyReady?.call(storedId);
}
