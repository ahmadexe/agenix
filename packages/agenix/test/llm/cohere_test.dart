import 'dart:typed_data';

import 'package:agenix/src/llm/_cohere.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  group('Cohere', () {
    late _MockDio dio;
    late Cohere llm;

    setUp(() {
      dio = _MockDio();
      llm = Cohere(
        apiKey: 'k',
        modelName: 'command-r-plus-08-2024',
        client: dio,
      );
    });

    test('extracts message.content[0].text', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/chat'),
          statusCode: 200,
          data: {
            'message': {
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': '  hi  '},
              ],
            },
            'finish_reason': 'COMPLETE',
          },
        ),
      );
      expect(await llm.generate(prompt: 'x'), 'hi');
    });

    test('rejects multimodal input', () async {
      expect(
        () => llm.generate(prompt: 'x', rawData: Uint8List(0)),
        throwsA(isA<LlmException>()),
      );
    });
  });
}
