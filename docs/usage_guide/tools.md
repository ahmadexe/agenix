# Working with Tools

Tools let your agent take actions in the real world — call APIs, query databases, perform calculations, control devices, and more. Without tools, an agent can only generate text. With tools, it can *do things*.

## How Tools Work

```
User: "What's the weather in Tokyo?"
         │
         ▼
┌─────────────────┐
│     Agent        │
│                  │
│  1. Sends prompt │──▶ LLM decides: "I need the weather tool"
│     to LLM       │
│                  │
│  2. Runs tool    │──▶ WeatherTool.run({city: "Tokyo"})
│                  │         │
│                  │         ▼
│                  │    API returns: "22°C, sunny"
│                  │
│  3. (Optional)   │──▶ LLM synthesizes: "It's 22°C and sunny
│     Reason over  │    in Tokyo — great weather for sightseeing!"
│     tool output  │
└─────────────────┘
         │
         ▼
User sees: "It's 22°C and sunny in Tokyo — great weather for sightseeing!"
```

The LLM decides *when* to use a tool and *what parameters* to pass. You define *what the tool does*.

## Creating a Tool

Extend the `Tool` class:

```dart
import 'package:agenix/agenix.dart';

class WeatherTool extends Tool {
  WeatherTool()
      : super(
          name: 'get_weather',
          description: 'Gets the current weather for a given city.',
          parameters: [
            ParameterSpecification(
              name: 'city',
              type: 'string',
              description: 'The city name to get weather for.',
              required: true,
            ),
          ],
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    final city = params['city'] as String;

    // Call your weather API here
    final weather = await WeatherApi.getCurrent(city);

    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: 'Weather in $city: ${weather.temp}°C, ${weather.condition}',
      data: {
        'temperature': weather.temp,
        'condition': weather.condition,
        'humidity': weather.humidity,
      },
      needsFurtherReasoning: true, // let the LLM craft a natural response
    );
  }
}
```

## Parameter Types

Define what inputs your tool accepts using `ParameterSpecification`:

```dart
parameters: [
  // Required string parameter
  ParameterSpecification(
    name: 'query',
    type: 'string',
    description: 'The search query.',
    required: true,
  ),

  // Optional number with default
  ParameterSpecification(
    name: 'limit',
    type: 'number',
    description: 'Maximum number of results.',
    required: false,
    defaultValue: 10,
  ),

  // Boolean parameter
  ParameterSpecification(
    name: 'include_details',
    type: 'boolean',
    description: 'Whether to include detailed information.',
    required: false,
    defaultValue: false,
  ),

  // Enum parameter (restricted values)
  ParameterSpecification(
    name: 'sort_by',
    type: 'string',
    description: 'How to sort results.',
    required: false,
    enumValues: ['relevance', 'date', 'popularity'],
    defaultValue: 'relevance',
  ),
]
```

Supported types: `string`, `number`, `boolean`, `object`, `array`

## Registering Tools

Tools are registered via the agent's `ToolRegistry`:

```dart
final agent = await Agent.create(
  dataStore: DataStore.inMemory(),
  llm: llm,
  name: 'assistant',
  role: 'A helpful assistant with access to weather and search tools.',
);

// Register tools
agent.toolRegistry.registerTool(WeatherTool());
agent.toolRegistry.registerTool(SearchTool());
agent.toolRegistry.registerTool(CalculatorTool());
```

You can also manage tools dynamically:

```dart
// Check if a tool is registered
if (agent.toolRegistry.hasTool('get_weather')) {
  print('Weather tool is available');
}

// Get a specific tool
final tool = agent.toolRegistry.getTool('search');

// List all registered tools
final allTools = agent.toolRegistry.getAllTools();

// Remove a tool
agent.toolRegistry.unregisterTool('get_weather');
```

## Tool Response

Every tool returns a `ToolResponse`:

```dart
ToolResponse(
  toolName: 'my_tool',
  isRequestSuccessful: true,       // did the tool succeed?
  message: 'Human-readable result', // shown to the LLM
  data: {'key': 'value'},           // optional structured data
  needsFurtherReasoning: false,     // should the LLM process this further?
)
```

### `needsFurtherReasoning`

This is the key decision when building a tool:

- **`false`** (default) — The tool's `message` is returned directly to the user. Use this when the tool's output is already a good response (e.g., "Item added to cart").

- **`true`** — The agent makes a second LLM call, passing the tool's output as context. The LLM then crafts a natural-language response. Use this when the tool returns raw data that needs to be summarized or explained (e.g., API responses, database results).

```dart
// Direct response — no further reasoning needed
return ToolResponse(
  toolName: name,
  isRequestSuccessful: true,
  message: 'Successfully added "Milk" to your shopping list.',
  needsFurtherReasoning: false, // this message goes straight to the user
);

// Raw data — let the LLM make sense of it
return ToolResponse(
  toolName: name,
  isRequestSuccessful: true,
  message: '{"results": [{"title": "Flutter Guide", "rating": 4.8}, ...]}',
  data: searchResults,
  needsFurtherReasoning: true, // LLM will summarize this nicely
);
```

### Handling Failures

When a tool fails, return a failure response:

```dart
@override
Future<ToolResponse> run(Map<String, dynamic> params) async {
  try {
    final result = await callExternalApi(params);
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: result.toString(),
    );
  } catch (e) {
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: false,
      message: 'Failed to fetch data: ${e.toString()}',
    );
  }
}
```

## Complete Example: Recipe Assistant

An agent with tools for searching recipes and converting measurements:

```dart
// --- Tool 1: Search Recipes ---
class RecipeSearchTool extends Tool {
  RecipeSearchTool()
      : super(
          name: 'search_recipes',
          description: 'Searches for recipes by ingredient or dish name.',
          parameters: [
            ParameterSpecification(
              name: 'query',
              type: 'string',
              description: 'The ingredient or dish to search for.',
              required: true,
            ),
            ParameterSpecification(
              name: 'dietary',
              type: 'string',
              description: 'Dietary restriction filter.',
              required: false,
              enumValues: ['none', 'vegetarian', 'vegan', 'gluten-free'],
              defaultValue: 'none',
            ),
          ],
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    final query = params['query'] as String;
    final dietary = params['dietary'] as String? ?? 'none';

    // Your recipe API call here
    final recipes = await RecipeApi.search(query, dietary: dietary);

    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: recipes.map((r) => '${r.name} (${r.time} min)').join('\n'),
      data: {'recipes': recipes.map((r) => r.toMap()).toList()},
      needsFurtherReasoning: true, // let the LLM present these nicely
    );
  }
}

// --- Tool 2: Unit Converter ---
class UnitConverterTool extends Tool {
  UnitConverterTool()
      : super(
          name: 'convert_units',
          description: 'Converts cooking measurement units.',
          parameters: [
            ParameterSpecification(
              name: 'value',
              type: 'number',
              description: 'The numeric value to convert.',
              required: true,
            ),
            ParameterSpecification(
              name: 'from_unit',
              type: 'string',
              description: 'The source unit.',
              required: true,
              enumValues: ['cups', 'tablespoons', 'teaspoons', 'ml', 'liters', 'oz', 'grams'],
            ),
            ParameterSpecification(
              name: 'to_unit',
              type: 'string',
              description: 'The target unit.',
              required: true,
              enumValues: ['cups', 'tablespoons', 'teaspoons', 'ml', 'liters', 'oz', 'grams'],
            ),
          ],
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    final value = (params['value'] as num).toDouble();
    final from = params['from_unit'] as String;
    final to = params['to_unit'] as String;

    final result = _convert(value, from, to);

    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: '$value $from = $result $to',
      needsFurtherReasoning: false, // simple enough to return directly
    );
  }

  double _convert(double value, String from, String to) {
    // conversion logic here
    return value; // placeholder
  }
}

// --- Putting it together ---
Future<Agent> createRecipeAssistant(String apiKey) async {
  final agent = await Agent.create(
    dataStore: DataStore.inMemory(),
    llm: LLM.geminiLLM(
      apiKey: apiKey,
      modelName: 'gemini-2.0-flash',
    ),
    name: 'recipe-assistant',
    role: 'A cooking assistant that helps users find recipes and '
        'convert measurements. Be warm and encouraging.',
  );

  agent.toolRegistry.registerTool(RecipeSearchTool());
  agent.toolRegistry.registerTool(UnitConverterTool());

  return agent;
}
```

Now when a user asks "Find me a vegan pasta recipe", the agent will automatically use the `search_recipes` tool with `query: "pasta"` and `dietary: "vegan"`.

## Multi-Tool Calls

The LLM can invoke multiple tools in a single turn. For example, if a user asks "What's the weather in Tokyo and New York?", the agent might call the weather tool twice. Agenix handles this automatically — the tool loop runs up to **5 iterations** per turn, accumulating results before responding.

You don't need to do anything special to enable this. Just register your tools and the LLM will decide when to use multiple tools.

## Best Practices

1. **Name tools clearly.** Use `snake_case` verbs: `search_recipes`, `get_weather`, `send_email`. The LLM uses the name to decide when to call the tool.

2. **Write detailed descriptions.** The description tells the LLM *when* to use the tool. Be specific:
   - Bad: `"Gets data"`
   - Good: `"Searches the product catalog by name, category, or price range. Returns up to 10 matching products with prices and availability."`

3. **Describe parameters thoroughly.** Include what valid values look like:
   - Bad: `description: "The date"`
   - Good: `description: "The date in YYYY-MM-DD format, e.g. 2024-03-15"`

4. **Use `needsFurtherReasoning` wisely.**
   - Raw API data → `true` (let the LLM summarize)
   - Simple confirmations → `false` (return directly)
   - Error messages → `false` (let the user see the exact error)

5. **Handle errors gracefully.** Always catch exceptions in `run()` and return a failure `ToolResponse` rather than letting exceptions bubble up.

6. **Keep tools focused.** One tool = one capability. Don't build a "do everything" tool. Multiple small tools give the LLM more flexibility. These tools can rup upto a depth of 5. 

## Next Steps

- Combine tools with multiple agents in [Multi-Agent Architecture](multi_agent.md)
- Persist tool-assisted conversations with [Memory & Persistence](memory_and_persistence.md)
