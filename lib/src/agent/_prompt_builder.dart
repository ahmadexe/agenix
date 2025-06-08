/// Builds the prompt for the LLM based on memory, system instructions,
/// THIS FILE IS NOT PART OF THE PUBLIC API
// INTERNAL: Changes here affect prompt structure and downstream LLM behaviors.
// Use extreme caution when modifying rules, formats, or instruction wording.


part of 'agent.dart';
class _PromptBuilder {
  final Map<String, dynamic> systemPrompt;
  final ToolRegistry registry;

  _PromptBuilder({required this.systemPrompt, required this.registry});

  String buildTextPrompt({
    List<AgentMessage>? memoryMessages,
    required AgentMessage userMessage,
    bool isPartOfChain = false,
    String? input,
  }) {
    final buffer = StringBuffer();

    buffer.writeln("RETURN THE RESPONSE IN JSON FORMAT ONLY");

    buffer.writeln("System Instruction: $systemPrompt\n");

    if (!isPartOfChain) {
      buffer.writeln(
        "Agents in the System: ${_AgentRegistry.instance.getAllAgents().map((e) => e.toString()).join(", ")}",
      );
    }

    if (memoryMessages != null && memoryMessages.isNotEmpty) {
      buffer.writeln("Chat History: ");
      for (final msg in memoryMessages) {
        buffer.writeln(
          "${msg.isFromAgent ? 'Chatbot' : 'User'}: ${msg.content}",
        );
      }
    }

    final tools = registry.getAllTools();
    if (tools.isNotEmpty) {
      buffer.writeln("Tools: ");
      for (final tool in tools) {
        buffer.writeln(
          "{${tool.name}: Description: ${tool.description}, Parameters: ${tool.parameters?.map((e) => e!.toJson())}},",
        );
      }
    }

    buffer.writeln('''
    \nOutput format if no tools are available for the prompt:
    {
      "response": "<response>"
    }
    Output if parameters are REQUIRED for the tool but are not given:
    {
    "response": "Please provide <param_name1>, <param_name2>, ...",
    "tools": "<tool_name>",
    }
    Output format if tools are available for the prompt:
    {
      "tools": "<tool_name>, <tool2_name>, ...",
      "parameters": {
        "<tool_name>": {
          "<param_name>": "<param_value>",
          ...
        },
        ...
      },
    }
    ''');

    if (!isPartOfChain) {
      buffer.writeln(
        '''Output format if the user's tasks needs to be handled by multiple agents in the system:
      {
        "agents_chain": ["<agent_name1>", "<agent_name2>", ...]"
      }\n''',
      );
    }

    // Instructions about how to use tools
    buffer.writeln('''
        RULE TO USE TOOLS:
        If a tool should be used and parameters are not provided in data, check if 'Provided Data' is available.
        If yes, use it to extract parameters. Only if a required parameter is completely missing from both the prompt AND the provided data, ask the user for it.
        NEVER ask the user if 'Provided Data' already has enough information. Do not mention the tool name in the response.
      ''');

    // Instructions about how to use agents
    if (!isPartOfChain) {
      buffer.writeln(
        "RULE TO USE AGENTS: If this tasks should be handled by multiple agents in the system, output a chain of agents in the logical sequence. This will be decided based on the available tools and available agents. If the tools available to you can't completely solve this task and the roles of available agents overlap with some part of the task and the prompt isn't of general nature that can be handled by any LLM/agent, then output the agents that should be used in the chain, in the sequential order of subtask hadnling.\n",
      );
    }

    buffer.writeln(
      "${"\nBased on the system instruction, chat history, tools and agents in the system, generate a response for the user. If a tool should be used for the response, include the tool name in the response, if parameters are required for a tool, include them in the response, if no parameters are required, do not include them. If no tool is available for the prompt, generate the response yourself. If agents should be used, output a chain of agents in the logical sequence. Give the response strictly in JSON, do not add anything extra to the response, just the parsable JSON. Do not include any text outside of the JSON. Order of action should be as follows: 1. Check all the available tools. \n2. If a tool or tools are found to respond to the prompt then output them in the provided JSON format. \n3. If a tool has a parameter that is required, deduce it from the given information and the prompt. If a parameters can not be deduced, ask the user to provide that paramter in the response field of the JSON. ONLY ASK FOR PARAMETERS IF THEY ARE REQUIRED, IF A PARAMETER IS NOT REQUIRED, DO NOT ASK FOR IT. DO NOT MENTION THE NAME OF THE TOOL IN THE RESPONSE, THEY ARE ONLY FOR INTERNAL USE"}\n",
    );

    // If data is provided as input from some previous execution in the chain, add it to the prompt
    if (input != null && input.isNotEmpty && isPartOfChain) {
      buffer.writeln(
        "DO NOT ASK FOR ANY ADDITIONAL CONTEXT, WORK WITH THE DATA THAT IS PROVIDED TO YOU. Use this data to perform the task, if tools are to be used for the task, find the parameters from this data, if parameters can be extracted from this data, extract them, otherwise DO NOT ASK THE USER FOR THE PARAMETERS, try and solve the task using this only this data and the data already available to you. Your highest priority should be to use this data and infer any required infromation, DO NOT ASK FOR ANY ADDITIONAL INFORMATION. Provided Data: $input\n",
      );
    }

    if (!isPartOfChain) {
      buffer.writeln(
        "${"\n4. If this tasks involve multiple agents in the system, output a chain of agents in the logical sequence. \n5. If it does not involve multiple agents in the system, and the task can not be solved completely by the tools available for the prompt, generate the response yourself. \n6. Always verrify if the task can be solved by agents or the given tools. \nThis is the user prompt: "}: ${userMessage.content}\n",
      );
    } else {
      buffer.writeln(
        "${"\n4. If no tool is available for the prompt, generate the response yourself. \nThis is the user prompt: "}: ${userMessage.content}\n",
      );
    }

    return buffer.toString().trim();
  }
}
