import 'package:agenix/src/llm/_openai.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  group('OpenAI', () {
    late _MockDio dio;
    late OpenAI llm;

    setUp(() {
      dio = _MockDio();
      llm = OpenAI(apiKey: 'k', modelName: 'gpt-4o', client: dio);
    });

    test('extracts choices[0].message.content', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/chat/completions'),
          statusCode: 200,
          data: {
            'choices': [
              {
                'message': {'content': '  hi  '},
                'finish_reason': 'stop',
              },
            ],
          },
        ),
      );
      expect(await llm.generate(prompt: 'x'), 'hi');
    });

    test('throws on empty content', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/chat/completions'),
          statusCode: 200,
          data: {
            'choices': [
              {
                'message': {'content': ''},
              },
            ],
          },
        ),
      );
      expect(() => llm.generate(prompt: 'x'), throwsA(isA<LlmException>()));
    });
  });
}
