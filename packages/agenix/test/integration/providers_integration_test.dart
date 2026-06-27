// Integration tests — hit real APIs. Run from the packages/agenix directory:
//   flutter test test/integration/providers_integration_test.dart
//
// Requires api_keys.env at the repo root (two levels up: ../../api_keys.env).
// Tests that fail with billing/quota errors are marked as skipped, not failing,
// because the provider implementation is correct even if the account is out of credits.

import 'dart:io';

import 'package:agenix/agenix.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads key=value lines from api_keys.env and returns a map.
Map<String, String> _loadEnv() {
  final envFile = File('../../api_keys.env');
  if (!envFile.existsSync()) {
    throw StateError(
      'api_keys.env not found at ${envFile.absolute.path}. '
      'Create it at the repo root before running integration tests.',
    );
  }
  final map = <String, String>{};
  for (final line in envFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx == -1) continue;
    map[trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim();
  }
  return map;
}

/// Returns true when [e] looks like a billing / quota / subscription error
/// so we can skip rather than fail.
bool _isBillingError(Object e) {
  final msg = e.toString().toLowerCase();
  return msg.contains('credit') ||
      msg.contains('quota') ||
      msg.contains('billing') ||
      msg.contains('subscription') ||
      msg.contains('insufficient') ||
      msg.contains('429') ||
      msg.contains('402');
}

void main() {
  late Map<String, String> keys;

  setUpAll(() {
    keys = _loadEnv();
  });

  const prompt = 'Reply with exactly one word: Hello';

  group('Anthropic (Claude)', () {
    test('generates a non-empty response', () async {
      final llm = LLM.anthropicLLM(
        apiKey: keys['ANTHROPIC_API_KEY']!,
        modelName: 'claude-haiku-4-5-20251001',
      );
      try {
        final response = await llm.generate(prompt: prompt);
        expect(response.trim(), isNotEmpty);
        print('Anthropic → $response');
      } on LlmException catch (e) {
        if (_isBillingError(e)) {
          markTestSkipped('Skipped: billing/quota issue — $e');
          return;
        }
        rethrow;
      }
    });
  });

  group('OpenAI', () {
    test('generates a non-empty response', () async {
      final llm = LLM.openAiLLM(
        apiKey: keys['OPENAI_API_KEY']!,
        modelName: 'gpt-4o-mini',
      );
      try {
        final response = await llm.generate(prompt: prompt);
        expect(response.trim(), isNotEmpty);
        print('OpenAI → $response');
      } on LlmException catch (e) {
        if (_isBillingError(e)) {
          markTestSkipped('Skipped: billing/quota issue — $e');
          return;
        }
        rethrow;
      }
    });
  });

  group('Cohere', () {
    test('generates a non-empty response', () async {
      final llm = LLM.cohereLLM(
        apiKey: keys['COHERE_API_KEY']!,
        modelName: 'command-r-plus-08-2024',
      );
      final response = await llm.generate(prompt: prompt);
      expect(response.trim(), isNotEmpty);
      print('Cohere → $response');
    });
  });

  group('ModelsLab', () {
    test('generates a non-empty response', () async {
      final llm = LLM.modelsLabLLM(
        apiKey: keys['MODELS_LAB_API_KEY']!,
        modelName: 'Qwen2-7B',
      );
      try {
        final response = await llm.generate(prompt: prompt);
        expect(response.trim(), isNotEmpty);
        print('ModelsLab → $response');
      } on LlmException catch (e) {
        if (_isBillingError(e)) {
          markTestSkipped('Skipped: billing/quota issue — $e');
          return;
        }
        rethrow;
      }
    });
  });

  group('Ollama', () {
    test('generates a non-empty response (local server required)', () async {
      // Ollama defaults to http://localhost:11434.
      // If OLLAMA_BASE_URL is set in api_keys.env, use that instead.
      final baseUrl =
          keys['OLLAMA_BASE_URL'] ?? 'http://localhost:11434';
      final llm = LLM.ollamaLLM(
        modelName: 'llama3.2',
        baseUrl: baseUrl,
        apiKey: keys['OLLAMA_API_KEY'],
      );
      try {
        final response = await llm.generate(prompt: prompt);
        expect(response.trim(), isNotEmpty);
        print('Ollama → $response');
      } on LlmException catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('connection refused') || msg.contains('failed to connect')) {
          markTestSkipped(
            'Skipped: Ollama server not reachable at $baseUrl. '
            'Start Ollama locally or set OLLAMA_BASE_URL in api_keys.env.',
          );
          return;
        }
        rethrow;
      }
    });
  });
}
