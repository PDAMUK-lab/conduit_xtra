/// `GET /api/local-models/status` — the node's local engine manager.
///
/// This manager is separate from a hand-run `llama-server`: on a node whose
/// worker is started outside it, [enabled] and [serverRunning] stay false while
/// a model is very much serving. The page says so rather than implying health.
final class HermesLocalModelStatus {
  const HermesLocalModelStatus({
    this.enabled = false,
    this.tag = '',
    this.updateAvailable = false,
    this.runtimeInstalled = false,
    this.runtimeBackend,
    this.serverRunning = false,
    this.serverBaseUrl,
    this.activeModelId,
    this.models = const [],
    this.modelsDir = '',
  });

  final bool enabled;
  final String tag;
  final bool updateAvailable;
  final bool runtimeInstalled;
  final String? runtimeBackend;
  final bool serverRunning;
  final String? serverBaseUrl;
  final String? activeModelId;
  final List<HermesLocalModel> models;
  final String modelsDir;

  int get modelCount => models.length;

  static HermesLocalModelStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final models = <HermesLocalModel>[];
    for (final row in (json['models'] as List? ?? const [])) {
      if (row is! Map) continue;
      final model = HermesLocalModel.fromJson(Map<String, dynamic>.from(row));
      if (model != null) models.add(model);
    }
    return HermesLocalModelStatus(
      enabled: json['enabled'] == true,
      tag: json['tag']?.toString() ?? '',
      updateAvailable: json['update_available'] == true,
      runtimeInstalled: json['runtime_installed'] == true,
      runtimeBackend: json['runtime_backend']?.toString(),
      serverRunning: json['server_running'] == true,
      serverBaseUrl: json['server_base_url']?.toString(),
      activeModelId: json['active_model_id']?.toString(),
      models: List.unmodifiable(models),
      modelsDir: json['models_dir']?.toString() ?? '',
    );
  }
}

/// One staged GGUF under the models directory.
final class HermesLocalModel {
  const HermesLocalModel({
    required this.id,
    this.name = '',
    this.sizeBytes = 0,
  });

  final String id;
  final String name;
  final int sizeBytes;

  static HermesLocalModel? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    final size = json['size_bytes'];
    return HermesLocalModel(
      id: id,
      name: json['name']?.toString() ?? '',
      sizeBytes: size is num ? size.toInt() : 0,
    );
  }
}

/// `GET /api/local-models/hardware` — what the card can actually fit.
final class HermesLocalHardware {
  const HermesLocalHardware({
    this.gpuName,
    this.vramTotalBytes = 0,
    this.vramUsableBytes = 0,
    this.vramUsedBytes,
    this.ramTotalBytes = 0,
    this.ramAvailableBytes = 0,
    this.uma = false,
    this.vramLabel = '',
  });

  final String? gpuName;
  final int vramTotalBytes;
  final int vramUsableBytes;
  final int? vramUsedBytes;
  final int ramTotalBytes;
  final int ramAvailableBytes;
  final bool uma;
  final String vramLabel;

  static int _int(Object? value) => value is num ? value.toInt().clamp(0, 1 << 50) : 0;

  static HermesLocalHardware? fromJson(Object? json) {
    if (json is! Map) return null;
    final used = json['vram_used_bytes'];
    return HermesLocalHardware(
      gpuName: json['gpu_name']?.toString(),
      vramTotalBytes: _int(json['vram_total_bytes']),
      vramUsableBytes: _int(json['vram_usable_bytes']),
      vramUsedBytes: used is num ? used.toInt() : null,
      ramTotalBytes: _int(json['ram_total_bytes']),
      ramAvailableBytes: _int(json['ram_available_bytes']),
      uma: json['uma'] == true,
      vramLabel: json['vram_label']?.toString() ?? '',
    );
  }
}
