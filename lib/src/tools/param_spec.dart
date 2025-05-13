// ParamSpecs are provided when a tool is defined
// and are used to validate the parameters passed to the tool.
// They are also used to generate the prompt for the LLM.
// The ParamSpec class defines the structure of a parameter specification.
// It includes the name, type, description, whether it is required,
// You can pass a complete API payload as the parameter value,
class ParamSpec {
  final String name;
  final String type; // 'string', 'number', 'boolean', 'object', 'array'
  final String description;
  final bool required;
  final dynamic defaultValue;
  final List<String>? enumValues;

  ParamSpec({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.defaultValue,
    this.enumValues,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'description': description,
    'required': required,
    if (defaultValue != null) 'default': defaultValue,
    if (enumValues != null) 'enum': enumValues,
  };
}
