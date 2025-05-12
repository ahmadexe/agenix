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

    if (parsed.containsKey("tools")) {
      final tools = (parsed["tools"] as String).split(',').map((t) => t.trim()).toList();
      final params = Map<String, Map<String, dynamic>>.from(parsed["parameters"]);
      return PromptParserResult(toolNames: tools, params: params);
    } else if (parsed.containsKey("response")) {
      return PromptParserResult(toolNames: [], params: {}, fallbackResponse: parsed["response"]);
    } else {
      throw Exception("Unrecognized format");
    }
  }

  Map<String, dynamic> _tryJsonDecode(String data) {
    try {
      return Map<String, dynamic>.from(jsonDecode(data));
    } catch (e) {
      throw Exception("Invalid JSON output from LLM");
    }
  }
}
