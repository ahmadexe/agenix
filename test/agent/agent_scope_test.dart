import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentScope', () {
    late AgentScope scope;
    setUp(() => scope = AgentScope());

    test('register and getAgent returns same object', () {
      final sentinel = Object();
      scope.registerAgent('a', sentinel);
      expect(scope.getAgent('a'), same(sentinel));
      expect(scope.hasAgent('a'), isTrue);
      expect(scope.getAllAgents(), contains(sentinel));
    });

    test('getAgent for unknown name returns null', () {
      expect(scope.getAgent('nope'), isNull);
      expect(scope.hasAgent('nope'), isFalse);
    });

    test('duplicate with throwIfExists throws ConfigException', () {
      scope.registerAgent('x', Object());
      expect(
        () => scope.registerAgent('x', Object()),
        throwsA(isA<ConfigException>()),
      );
    });

    test('duplicate with replace policy overwrites', () {
      final first = Object();
      final second = Object();
      scope.registerAgent('x', first);
      scope.registerAgent('x', second, policy: RegistrationPolicy.replace);
      expect(scope.getAgent('x'), same(second));
    });

    test('duplicate with ignore policy keeps original', () {
      final first = Object();
      scope.registerAgent('x', first);
      scope.registerAgent('x', Object(), policy: RegistrationPolicy.ignore);
      expect(scope.getAgent('x'), same(first));
    });

    test('unregister removes and allows re-registration', () {
      scope.registerAgent('x', Object());
      scope.unregisterAgent('x');
      expect(scope.getAgent('x'), isNull);
      expect(() => scope.registerAgent('x', Object()), returnsNormally);
    });

    test('clear empties the scope', () {
      scope.registerAgent('a', Object());
      scope.registerAgent('b', Object());
      scope.clear();
      expect(scope.getAllAgents(), isEmpty);
    });

    test('two scopes are isolated from each other', () {
      final scopeA = AgentScope();
      final scopeB = AgentScope();
      scopeA.registerAgent('x', Object());
      expect(scopeB.hasAgent('x'), isFalse);
    });

    test('AgentScope.global is independent of a fresh scope', () {
      final fresh = AgentScope();
      fresh.registerAgent('local', Object());
      expect(AgentScope.global.hasAgent('local'), isFalse);
    });
  });
}
