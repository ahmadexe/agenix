import 'package:agenix/src/tools/param_spec.dart';

/// Result of validating tool parameters against their specifications.
class ValidationResult {
  /// The validated and normalized parameter map.
  final Map<String, dynamic> values;

  /// Validation error messages, empty if validation passed.
  final List<String> errors;

  /// Whether validation passed with no errors.
  bool get isValid => errors.isEmpty;

  /// Creates a [ValidationResult].
  const ValidationResult({required this.values, required this.errors});
}

/// Validates a raw parameter map from the LLM against a tool's parameter specs.
///
/// Performs: required-field checks, enum enforcement, type coercion, default
/// injection, and stripping of unknown parameters.
ValidationResult validateParams(
  List<ParameterSpecification> specs,
  Map<String, dynamic> rawParams,
) {
  final validated = <String, dynamic>{};
  final errors = <String>[];
  final knownNames = specs.map((s) => s.name).toSet();

  for (final spec in specs) {
    final hasValue = rawParams.containsKey(spec.name) && rawParams[spec.name] != null;

    if (!hasValue) {
      if (spec.defaultValue != null) {
        validated[spec.name] = spec.defaultValue;
        continue;
      }
      if (spec.required) {
        errors.add('Missing required parameter: ${spec.name}');
        continue;
      }
      continue;
    }

    var value = rawParams[spec.name];

    // Enum check
    if (spec.enumValues != null && spec.enumValues!.isNotEmpty) {
      final asString = value.toString();
      if (!spec.enumValues!.contains(asString)) {
        errors.add(
          'Parameter ${spec.name} must be one of ${spec.enumValues}, got "$asString"',
        );
        continue;
      }
    }

    // Type coercion
    value = _coerce(value, spec.type, spec.name, errors);
    if (value == null && spec.required) {
      continue;
    }

    validated[spec.name] = value;
  }

  // Pass through unknown params (the LLM may send extra keys the tool handles)
  for (final key in rawParams.keys) {
    if (!knownNames.contains(key) && !validated.containsKey(key)) {
      validated[key] = rawParams[key];
    }
  }

  return ValidationResult(values: validated, errors: errors);
}

dynamic _coerce(
  dynamic value,
  String type,
  String paramName,
  List<String> errors,
) {
  switch (type) {
    case 'string':
      return value.toString();
    case 'number':
      if (value is num) return value;
      final parsed = num.tryParse(value.toString());
      if (parsed == null) {
        errors.add('Parameter $paramName: expected number, got "$value"');
        return null;
      }
      return parsed;
    case 'boolean':
      if (value is bool) return value;
      final s = value.toString().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
      errors.add('Parameter $paramName: expected boolean, got "$value"');
      return null;
    case 'object':
      if (value is Map) return Map<String, dynamic>.from(value);
      errors.add('Parameter $paramName: expected object, got ${value.runtimeType}');
      return null;
    case 'array':
      if (value is List) return value;
      errors.add('Parameter $paramName: expected array, got ${value.runtimeType}');
      return null;
    default:
      return value;
  }
}
