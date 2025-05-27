/// ParameterSpecifications are provided when a tool is defined
/// and are used to validate the parameters passed to the tool.
/// They are also used to generate the prompt for the LLM.
/// The ParamSpec class defines the structure of a parameter specification.
/// It includes the name, type, description, whether it is required,
/// You can pass a complete API payload as the parameter value,
class ParameterSpecification {
  /// The name of the parameter.
  final String name;

  /// The type of the parameter.
  final String type; // 'string', 'number', 'boolean', 'object', 'array'

  /// The description of the parameter.
  /// This should be a short description of what the parameter does.
  /// The better the description, the better the results.
  final String description;

  /// Whether the parameter is required or not.
  final bool required;

  /// The default value of the parameter.
  final dynamic defaultValue;

  /// The enum values of the parameter.
  /// This is used to restrict the values that can be passed to the parameter.
  /// This is useful for parameters that can only take a limited set of values.
  /// For example, a parameter that can only take the values 'red', 'green', or 'blue'.
  final List<String>? enumValues;

  /// Constructs a ParameterSpecification with the required fields.
  ParameterSpecification({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.defaultValue,
    this.enumValues,
  });

  /// Creates a copy of the current ParameterSpecification with optional new values.
  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'description': description,
    'required': required,
    if (defaultValue != null) 'default': defaultValue,
    if (enumValues != null) 'enum': enumValues,
  };
}
