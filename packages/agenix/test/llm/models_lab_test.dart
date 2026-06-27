import 'dart:typed_data';

import 'package:agenix/src/llm/_models_lab.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  group('ModelsLab', () {
    late _MockDio dio;
    late ModelsLab llm;

    setUp(() {
      dio = _MockDio();
      llm = ModelsLab(apiKey: 'k', modelName: 'Qwen2-7B', client: dio);
    });

    test('extracts output string', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/llm/chat'),
          statusCode: 200,
          data: {'status': 'success', 'output': '  hi  '},
        ),
      );
      expect(await llm.generate(prompt: 'x'), 'hi');
    });

    test('throws on non-success status', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/llm/chat'),
          statusCode: 200,
          data: {'status': 'error', 'message': 'bad key'},
        ),
      );
      expect(() => llm.generate(prompt: 'x'), throwsA(isA<LlmException>()));
    });

    test('rejects multimodal input', () async {
      expect(
        () => llm.generate(prompt: 'x', rawData: Uint8List(0)),
        throwsA(isA<LlmException>()),
      );
    });
  });
}
