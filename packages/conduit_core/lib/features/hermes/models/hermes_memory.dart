import 'package:conduit_core/features/hermes/services/hermes_identifier.dart';

/// Longest provider description the page shows.
const int kMaxHermesMemoryDescriptionCharacters = 1024;

/// One memory provider Hermes discovered, as `GET /api/memory` reports it.
///
/// `status` is the server's own word (`ready`, `unavailable`, …); switching to
/// a provider that is not ready is refused server-side, so the page treats
/// only `ready` as selectable and shows the rest with their reason.
final class HermesMemoryProvider {
  const HermesMemoryProvider({
    required this.name,
    required this.description,
    required this.status,
    this.available = false,
    this.configured = false,
  });

  final String name;
  final String description;
  final String status;
  final bool available;
  final bool configured;

  bool get ready => status == 'ready' && available;

  static HermesMemoryProvider? fromJson(Map<String, dynamic> json) {
    final name = validateHermesOpaqueIdentifier(json['name']);
    if (name == null) return null;
    final rawDescription = json['description']?.toString().trim() ?? '';
    final description =
        rawDescription.length > kMaxHermesMemoryDescriptionCharacters
        ? rawDescription.substring(0, kMaxHermesMemoryDescriptionCharacters)
        : rawDescription;
    final status =
        validateHermesBoundedString(json['status'], maxCharacters: 64) ?? '';
    return HermesMemoryProvider(
      name: name,
      description: description,
      status: status,
      available: json['available'] == true,
      configured: json['configured'] == true,
    );
  }
}

/// `GET /api/memory`: the active provider, every discovered provider, and the
/// built-in memory files' sizes (what a reset would erase).
final class HermesMemoryStatus {
  const HermesMemoryStatus({
    required this.active,
    required this.providers,
    this.memoryFileBytes = 0,
    this.userFileBytes = 0,
  });

  final String active;
  final List<HermesMemoryProvider> providers;
  final int memoryFileBytes;
  final int userFileBytes;

  bool get hasBuiltinFiles => memoryFileBytes > 0 || userFileBytes > 0;

  static HermesMemoryStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawProviders = json['providers'];
    final providers = <HermesMemoryProvider>[];
    if (rawProviders is List) {
      for (final row in rawProviders) {
        if (row is! Map) continue;
        final provider = HermesMemoryProvider.fromJson(
          Map<String, dynamic>.from(row),
        );
        if (provider != null) providers.add(provider);
      }
    }
    final files = json['builtin_files'];
    int sizeOf(String key) {
      if (files is! Map) return 0;
      final value = files[key];
      return value is num ? value.toInt().clamp(0, 1 << 40) : 0;
    }

    return HermesMemoryStatus(
      active: validateHermesBoundedString(
            json['active'],
            maxCharacters: 64,
            allowEmpty: true,
          ) ??
          '',
      providers: List.unmodifiable(providers),
      memoryFileBytes: sizeOf('memory'),
      userFileBytes: sizeOf('user'),
    );
  }
}
