import 'dart:convert';

/// The intent of the parsed LLM output.
enum ParseOutcome {
  /// The LLM produced a direct text response.
  response,

  /// The LLM requested one or more tools to be executed.
  tools,

  /// The LLM requested delegation to a chain of agents.
  agentsChain,

  /// The LLM output could not be parsed into any known shape.
  unparseable,
}

/// The result of parsing a raw LLM output string.
class PromptParserResult {
  /// The parsed intent of this result.
  final ParseOutcome outcome;

  /// Name of the agents that need to be engaged for the task at hand.
  final List<String> agentNames;

  /// Tool names that the LLM has requested to execute.
  final List<String> toolNames;

  /// A map of tool names to their parameters.
  final Map<String, Map<String, dynamic>> params;

  /// The text response from the LLM, when [outcome] is [ParseOutcome.response].
  final String? fallbackResponse;

  /// The raw LLM output string, preserved for retry/debug purposes.
  final String? rawOutput;

  /// Constructs a PromptParserResult.
  PromptParserResult({
    required this.outcome,
    required this.agentNames,
    required this.toolNames,
    required this.params,
    this.fallbackResponse,
    this.rawOutput,
  });
}

/// Parses the raw JSON output from the LLM into a structured result.
class PromptParser {
  /// Parses the LLM output and returns a [PromptParserResult].
  ///
  /// Never throws on shape variance — returns [ParseOutcome.unparseable] instead.
  PromptParserResult parse(String llmOutputJson) {
    final data = llmOutputJson.trim();
    final Map<String, dynamic>? parsed = _tryJsonDecode(data);

    if (parsed == null) {
      return PromptParserResult(
        outcome: ParseOutcome.unparseable,
        agentNames: [],
        toolNames: [],
        params: {},
        rawOutput: llmOutputJson,
      );
    }

    // Agent chain
    if (parsed.containsKey("agents_chain")) {
      final raw = parsed["agents_chain"];
      final List<String> names;
      if (raw is List) {
        names = raw.map((e) => e.toString()).toList();
      } else if (raw is String) {
        names = [raw];
      } else {
        return _unparseable(llmOutputJson);
      }
      return PromptParserResult(
        outcome: ParseOutcome.agentsChain,
        agentNames: names,
        toolNames: [],
        params: {},
        rawOutput: llmOutputJson,
      );
    }

    // Direct response
    if (parsed.containsKey("response")) {
      return PromptParserResult(
        outcome: ParseOutcome.response,
        agentNames: [],
        toolNames: [],
        params: {},
        fallbackResponse: parsed["response"]?.toString(),
        rawOutput: llmOutputJson,
      );
    }

    // Tool invocation
    if (parsed.containsKey("tools")) {
      final rawTools = parsed["tools"];
      final List<String> tools;
      if (rawTools is String) {
        tools =
            rawTools
                .split(',')
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty)
                .toList();
      } else if (rawTools is List) {
        tools =
            rawTools
                .map((e) => e.toString().trim())
                .where((t) => t.isNotEmpty)
                .toList();
      } else {
        return _unparseable(llmOutputJson);
      }

      final rawParams = parsed["parameters"];
      final Map<String, dynamic> rawParamsMap =
          rawParams is Map<String, dynamic> ? rawParams : {};

      final Map<String, Map<String, dynamic>> params = {
        for (String tool in tools)
          tool:
              rawParamsMap[tool] is Map
                  ? Map<String, dynamic>.from(rawParamsMap[tool])
                  : <String, dynamic>{},
      };

      return PromptParserResult(
        outcome: ParseOutcome.tools,
        toolNames: tools,
        params: params,
        agentNames: [],
        rawOutput: llmOutputJson,
      );
    }

    return _unparseable(llmOutputJson);
  }

  PromptParserResult _unparseable(String raw) => PromptParserResult(
    outcome: ParseOutcome.unparseable,
    agentNames: [],
    toolNames: [],
    params: {},
    rawOutput: raw,
  );

  /// Attempts to decode a JSON string, returning null on failure instead of throwing.
  Map<String, dynamic>? _tryJsonDecode(String data) {
    // Strip markdown fences
    data = data.replaceAll(RegExp(r'```(?:json)?', multiLine: true), '').trim();

    try {
      final decoded = json.decode(data);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      // Fallback: extract the first balanced JSON object from prose
      final start = data.indexOf('{');
      final end = data.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) return null;
      try {
        final decoded = json.decode(data.substring(start, end + 1));
        if (decoded is Map<String, dynamic>) return decoded;
        return null;
      } catch (_) {
        return null;
      }
    }
  }
}
