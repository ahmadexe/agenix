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
