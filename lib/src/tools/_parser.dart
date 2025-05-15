import 'dart:convert';

// The parser is responsible for interpreting the output from the LLM.
// The output is in JSON format and can contain either a response or a list of tools to be executed.
// The parser will extract the tool names and parameters from the JSON output.
// It will also handle the case where the LLM asks for parameters to be provided.
// The parser will throw an exception if the output is not in the expected format.

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

/// The PromptParser class is responsible for parsing the output from the LLM.
class PromptParser {
  PromptParserResult parse(String llmOutputJson) {
    final data = llmOutputJson.trim();
    final Map<String, dynamic> parsed = _tryJsonDecode(data);
    // Check if the parsed data contains a "response" key
    // If it does, return the response as a fallback
    // If it doesn't, check if it contains a "tools" key
    // If it does, extract the tool names and parameters
    // If it doesn't, throw an exception
    // indicating that the format is unrecognized
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
        for (String tool in tools)
          tool: Map<String, dynamic>.from(rawParamsMap[tool] ?? {}),
      };

      return PromptParserResult(toolNames: tools, params: params);
    } else {
      throw Exception("Unrecognized format");
    }
  }

  /// Attempts to decode a JSON string.
  /// If the string is not valid JSON, it throws an exception.
  /// This method is used to handle the case where the LLM output is not in the expected format.
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
