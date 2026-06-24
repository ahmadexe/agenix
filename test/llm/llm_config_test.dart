import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LlmConfig', () {
    test('default values', () {
      const cfg = LlmConfig();
      expect(cfg.temperature, 0.2);
      expect(cfg.maxOutputTokens, isNull);
      expect(cfg.topP, isNull);
      expect(cfg.topK, isNull);
      expect(cfg.stopSequences, isNull);
      expect(cfg.jsonMode, isTrue);
      expect(cfg.timeout, const Duration(seconds: 60));
    });

    test('copyWith with no args yields equal values', () {
      const original = LlmConfig(temperature: 0.5, maxOutputTokens: 1024);
      final copy = original.copyWith();
      expect(copy.temperature, original.temperature);
      expect(copy.maxOutputTokens, original.maxOutputTokens);
      expect(copy.jsonMode, original.jsonMode);
      expect(copy.timeout, original.timeout);
    });

    test('copyWith overrides specified fields only', () {
      const original = LlmConfig(temperature: 0.5, maxOutputTokens: 1024);
      final copy = original.copyWith(temperature: 0.9);
      expect(copy.temperature, 0.9);
      expect(copy.maxOutputTokens, 1024);
    });

    test('custom values are preserved', () {
      final cfg = LlmConfig(
        temperature: 0.0,
        maxOutputTokens: 256,
        topP: 0.95,
        topK: 40,
        stopSequences: ['STOP'],
        jsonMode: false,
        timeout: const Duration(seconds: 30),
      );
      expect(cfg.temperature, 0.0);
      expect(cfg.maxOutputTokens, 256);
      expect(cfg.topP, 0.95);
      expect(cfg.topK, 40);
      expect(cfg.stopSequences, ['STOP']);
      expect(cfg.jsonMode, isFalse);
      expect(cfg.timeout, const Duration(seconds: 30));
    });
  });
}
