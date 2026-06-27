import 'package:agenix/src/llm/_anthropic.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  group('Anthropic', () {
    late _MockDio dio;
    late Anthropic llm;

    setUp(() {
      dio = _MockDio();
      llm = Anthropic(
        apiKey: 'test-key',
        modelName: 'claude-sonnet-4-5',
        client: dio,
      );
    });

    test('returns text from content[0].text', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/messages'),
          statusCode: 200,
          data: {
            'content': [
              {'type': 'text', 'text': '  hello  '},
            ],
          },
        ),
      );

      final result = await llm.generate(prompt: 'hi');
      expect(result, 'hello');
    });

    test('throws LlmException on Dio error', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/messages'),
          response: Response(
            requestOptions: RequestOptions(path: '/messages'),
            statusCode: 401,
          ),
        ),
      );

      expect(() => llm.generate(prompt: 'hi'), throwsA(isA<LlmException>()));
    });

    test('throws LlmException on empty content', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/messages'),
          statusCode: 200,
          data: {'content': []},
        ),
      );

      expect(() => llm.generate(prompt: 'hi'), throwsA(isA<LlmException>()));
    });
  });
}
