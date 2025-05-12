import 'dart:convert';

class PromptParserResult {
  final List<String> toolNames;
  final Map<String, Map<String, dynamic>> params;
  final String? fallbackResponse;

  PromptParserResult({
    required this.toolNames,
    required this.params,
    this.fallbackResponse,
  });
}

class PromptParser {
  PromptParserResult parse(String llmOutputJson) {
    final data = llmOutputJson.trim();
    final Map<String, dynamic> parsed = _tryJsonDecode(data);
    if (parsed.containsKey("response")) {
      return PromptParserResult(
        toolNames: [],
        params: {},
        fallbackResponse: parsed["response"],
      );
    } else if (parsed.containsKey("tools")) {
      final tools =
          (parsed["tools"] as String)
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList();

      final rawParams = parsed["parameters"];
      final Map<String, dynamic> rawParamsMap =
          rawParams is Map<String, dynamic> ? rawParams : {};

      final Map<String, Map<String, dynamic>> params = {
        for (var tool in tools)
          tool: Map<String, dynamic>.from(rawParamsMap[tool] ?? {}),
      };

      return PromptParserResult(toolNames: tools, params: params);
    } else {
      throw Exception("Unrecognized format");
    }
  }

  Map<String, dynamic> _tryJsonDecode(String data) {
    try {
      data = data.replaceFirst(RegExp(r'```json'), '');
      data = data.replaceFirst(RegExp(r'```'), '');
      return json.decode(data);
    } catch (e) {
      throw Exception("Invalid JSON output from LLM: $e");
    }
  }
}
