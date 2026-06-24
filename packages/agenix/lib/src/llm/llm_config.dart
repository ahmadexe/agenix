/// Provider-neutral generation settings for LLM calls.
class LlmConfig {
  /// Sampling temperature (0.0 = deterministic). Low default suits structured JSON output.
  final double? temperature;

  /// Hard cap on output tokens (cost/latency control).
  final int? maxOutputTokens;

  /// Nucleus sampling threshold.
  final double? topP;

  /// Top-K sampling limit.
  final int? topK;

  /// Sequences that cause the model to stop generating.
  final List<String>? stopSequences;

  /// Request the provider's native JSON output mode where supported.
  final bool jsonMode;

  /// Per-request wall-clock timeout.
  final Duration timeout;

  /// Creates an [LlmConfig] with sensible defaults for structured JSON output.
  const LlmConfig({
    this.temperature = 0.2,
    this.maxOutputTokens,
    this.topP,
    this.topK,
    this.stopSequences,
    this.jsonMode = true,
    this.timeout = const Duration(seconds: 60),
  });

  /// Returns a copy with the given fields replaced.
  LlmConfig copyWith({
    double? temperature,
    int? maxOutputTokens,
    double? topP,
    int? topK,
    List<String>? stopSequences,
    bool? jsonMode,
    Duration? timeout,
  }) {
    return LlmConfig(
      temperature: temperature ?? this.temperature,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      stopSequences: stopSequences ?? this.stopSequences,
      jsonMode: jsonMode ?? this.jsonMode,
      timeout: timeout ?? this.timeout,
    );
  }
}
