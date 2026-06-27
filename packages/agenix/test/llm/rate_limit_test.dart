import 'package:agenix/agenix.dart';
import 'package:agenix/src/llm/_anthropic.dart';
import 'package:agenix/src/llm/_cohere.dart';
import 'package:agenix/src/llm/_openai.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

DioException _dioError(
  int status, {
  Map<String, List<String>> headers = const {},
}) {
  final opts = RequestOptions(path: '/');
  return DioException(
    requestOptions: opts,
    response: Response(
      requestOptions: opts,
      statusCode: status,
      headers: Headers.fromMap(headers),
    ),
  );
}

Future<Object> _capture(Future<void> Function() fn) async {
  try {
    await fn();
    fail('Expected an exception');
  } catch (e) {
    return e;
  }
}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  for (final entry in <(String, (_MockDio, LLM) Function())>[
    (
      'OpenAI',
      () {
        final dio = _MockDio();
        return (dio, OpenAI(apiKey: 'k', modelName: 'gpt-4o', client: dio));
      },
    ),
    (
      'Anthropic',
      () {
        final dio = _MockDio();
        return (
          dio,
          Anthropic(apiKey: 'k', modelName: 'claude-sonnet-4-5', client: dio),
        );
      },
    ),
    (
      'Cohere',
      () {
        final dio = _MockDio();
        return (
          dio,
          Cohere(apiKey: 'k', modelName: 'command-r-plus-08-2024', client: dio),
        );
      },
    ),
  ]) {
    final providerName = entry.$1;
    final factory = entry.$2;

    group(providerName, () {
      test(
        '429 with Retry-After header → LlmRateLimitException with retryAfter set',
        () async {
          final (dio, llm) = factory();
          when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
            _dioError(
              429,
              headers: {
                'retry-after': ['30'],
              },
            ),
          );

          final e = await _capture(() => llm.generate(prompt: 'x'));

          expect(e, isA<LlmRateLimitException>());
          final rle = e as LlmRateLimitException;
          expect(rle.statusCode, 429);
          expect(rle.retryAfter, const Duration(seconds: 30));
        },
      );

      test(
        '429 without Retry-After header → LlmRateLimitException with retryAfter null',
        () async {
          final (dio, llm) = factory();
          when(
            () => dio.post(any(), data: any(named: 'data')),
          ).thenThrow(_dioError(429));

          final e = await _capture(() => llm.generate(prompt: 'x'));

          expect(e, isA<LlmRateLimitException>());
          final rle = e as LlmRateLimitException;
          expect(rle.statusCode, 429);
          expect(rle.retryAfter, isNull);
        },
      );

      test(
        'non-429 error → LlmException (not LlmRateLimitException) with statusCode set',
        () async {
          final (dio, llm) = factory();
          when(
            () => dio.post(any(), data: any(named: 'data')),
          ).thenThrow(_dioError(503));

          final e = await _capture(() => llm.generate(prompt: 'x'));

          expect(e, isA<LlmException>());
          expect(e, isNot(isA<LlmRateLimitException>()));
          expect((e as LlmException).statusCode, 503);
        },
      );
    });
  }
}
