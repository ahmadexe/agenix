import 'package:agenix/agenix.dart';
import 'package:agenix/src/tools/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/spy_tool.dart';

void main() {
  group('ToolRegistry', () {
    late ToolRegistry reg;
    setUp(() => reg = ToolRegistry());

    test('registers and retrieves a tool', () {
      final t = SpyTool(name: 'weather');
      reg.registerTool(t);
      expect(reg.getTool('weather'), same(t));
      expect(reg.hasTool('weather'), isTrue);
    });

    test('getTool returns null for unknown name', () {
      expect(reg.getTool('nope'), isNull);
      expect(reg.hasTool('nope'), isFalse);
    });

    test('throws ConfigException on duplicate name', () {
      reg.registerTool(SpyTool(name: 'dup'));
      expect(
        () => reg.registerTool(SpyTool(name: 'dup')),
        throwsA(isA<ConfigException>()),
      );
    });

    test('unregister removes the tool and allows re-registration', () {
      reg.registerTool(SpyTool(name: 'x'));
      reg.unregisterTool('x');
      expect(reg.getTool('x'), isNull);
      expect(() => reg.registerTool(SpyTool(name: 'x')), returnsNormally);
    });

    test('getAllTools returns all registered tools', () {
      reg.registerTool(SpyTool(name: 'a'));
      reg.registerTool(SpyTool(name: 'b'));
      expect(reg.getAllTools(), hasLength(2));
    });

    test('unregister of absent name is a no-op', () {
      expect(() => reg.unregisterTool('nope'), returnsNormally);
    });
  });
}
