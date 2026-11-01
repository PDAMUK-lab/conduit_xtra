/// Numbers from `GET /api/analytics/usage` and `/api/analytics/models`.
///
/// The dashboard reports tokens, costs and call counts; the app shows them as
/// read-only totals and a per-model breakdown. Nothing here writes.
final class HermesUsageTotals {
  const HermesUsageTotals({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.reasoningTokens = 0,
    this.estimatedCost = 0,
    this.actualCost = 0,
    this.sessions = 0,
    this.apiCalls = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int reasoningTokens;
  final double estimatedCost;
  final double actualCost;
  final int sessions;
  final int apiCalls;

  int get totalTokens => inputTokens + outputTokens;

  static double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _int(Object? value) => _num(value).round().clamp(0, 1 << 50);

  /// The `/usage` totals block uses `total_*` names; the `/models` one the
  /// plain names. Accept both.
  static HermesUsageTotals fromJson(Object? json) {
    if (json is! Map) return const HermesUsageTotals();
    return HermesUsageTotals(
      inputTokens: _int(json['total_input'] ?? json['input_tokens']),
      outputTokens: _int(json['total_output'] ?? json['output_tokens']),
      cacheReadTokens: _int(
        json['total_cache_read'] ?? json['cache_read_tokens'],
      ),
      reasoningTokens: _int(
        json['total_reasoning'] ?? json['reasoning_tokens'],
      ),
      estimatedCost: _num(
        json['total_estimated_cost'] ?? json['estimated_cost'],
      ),
      actualCost: _num(json['total_actual_cost'] ?? json['actual_cost']),
      sessions: _int(json['total_sessions'] ?? json['sessions']),
      apiCalls: _int(json['total_api_calls'] ?? json['api_calls']),
    );
  }
}

/// One row of the per-model breakdown.
final class HermesModelUsage {
  const HermesModelUsage({
    required this.model,
    this.provider = '',
    this.totals = const HermesUsageTotals(),
    this.lastUsedAt = 0,
  });

  final String model;
  final String provider;
  final HermesUsageTotals totals;
  final double lastUsedAt;

  static HermesModelUsage? fromJson(Map<String, dynamic> json) {
    final model = (json['model']?.toString() ?? '').trim();
    if (model.isEmpty) return null;
    final last = json['last_used_at'];
    return HermesModelUsage(
      model: model,
      provider: (json['billing_provider']?.toString() ?? '').trim(),
      totals: HermesUsageTotals.fromJson(json),
      lastUsedAt: last is num
          ? last.toDouble()
          : double.tryParse(last?.toString() ?? '') ?? 0,
    );
  }
}

/// `GET /api/analytics/usage`.
final class HermesUsageAnalytics {
  const HermesUsageAnalytics({
    this.totals = const HermesUsageTotals(),
    this.byModel = const [],
    this.periodDays = 30,
    this.skills = const {},
    this.tools = const {},
  });

  final HermesUsageTotals totals;
  final List<HermesModelUsage> byModel;
  final int periodDays;

  /// Name → call count.
  final Map<String, int> skills;
  final Map<String, int> tools;

  static HermesUsageAnalytics? fromJson(Object? json) {
    if (json is! Map) return null;
    final models = <HermesModelUsage>[];
    for (final row in (json['by_model'] as List? ?? const [])) {
      if (row is! Map) continue;
      final model = HermesModelUsage.fromJson(Map<String, dynamic>.from(row));
      if (model != null) models.add(model);
    }
    Map<String, int> counts(Object? value) {
      if (value is! Map) return const {};
      final out = <String, int>{};
      value.forEach((key, raw) {
        final n = raw is num ? raw.toInt() : int.tryParse('$raw');
        if (n != null && key.toString().isNotEmpty) out[key.toString()] = n;
      });
      return out;
    }

    final days = json['period_days'];
    return HermesUsageAnalytics(
      totals: HermesUsageTotals.fromJson(json['totals']),
      byModel: List.unmodifiable(models),
      periodDays: days is num ? days.toInt() : 30,
      skills: counts(json['skills']),
      tools: counts(json['tools']),
    );
  }
}

/// `GET /api/analytics/models`.
final class HermesModelsAnalytics {
  const HermesModelsAnalytics({
    this.models = const [],
    this.totals = const HermesUsageTotals(),
    this.periodDays = 30,
    this.distinctModels = 0,
  });

  final List<HermesModelUsage> models;
  final HermesUsageTotals totals;
  final int periodDays;
  final int distinctModels;

  static HermesModelsAnalytics? fromJson(Object? json) {
    if (json is! Map) return null;
    final models = <HermesModelUsage>[];
    for (final row in (json['models'] as List? ?? const [])) {
      if (row is! Map) continue;
      final model = HermesModelUsage.fromJson(Map<String, dynamic>.from(row));
      if (model != null) models.add(model);
    }
    final totals = json['totals'];
    final distinct = totals is Map ? totals['distinct_models'] : null;
    final days = json['period_days'];
    return HermesModelsAnalytics(
      models: List.unmodifiable(models),
      totals: HermesUsageTotals.fromJson(totals),
      periodDays: days is num ? days.toInt() : 30,
      distinctModels: distinct is num ? distinct.toInt() : models.length,
    );
  }
}
