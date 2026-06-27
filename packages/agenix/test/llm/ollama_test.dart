import 'package:agenix/src/llm/_ollama.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  group('Ollama', () {
    late _MockDio dio;
    late Ollama llm;

    setUp(() {
      dio = _MockDio();
      llm = Ollama(modelName: 'llama3.2', client: dio);
    });

    test('extracts message.content', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/chat'),
          statusCode: 200,
          data: {
            'message': {'role': 'assistant', 'content': '  hi  '},
            'done': true,
          },
        ),
      );
      expect(await llm.generate(prompt: 'x'), 'hi');
    });

    test('throws on empty content', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/chat'),
          statusCode: 200,
          data: {'message': {'content': ''}, 'done': true},
        ),
      );
      expect(() => llm.generate(prompt: 'x'), throwsA(isA<LlmException>()));
    });
  });
}
