![Screenshot 2025-05-28 at 4 49 43 PM](https://github.com/user-attachments/assets/fbb110c9-6019-440b-b6c4-37d86dea725f)


# Agenix


<p align="center">
<a href="https://github.com/ahmadexe/agenix"><img src="https://img.shields.io/github/stars/ahmadexe/agenix.svg?style=flat&logo=github&colorB=deeppink&label=stars" alt="Star on Github"></a>
<a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-purple.svg" alt="License: MIT"></a>
<a href="https://pub.dev/packages/agenix"><img src="https://img.shields.io/pub/v/agenix.svg" alt="Pub Dev"></a>
<a href="https://pub.dev/packages/agenix"><img src="https://img.shields.io/badge/platform-Flutter%20%7C%20Dart-blue" alt="Platform"></a>
</p>

---

A framework to build agentic apps using Flutter & Dart!

---


## Overview
Agenix aims at providing an easy interface to build Agentic apps using Flutter and Dart. It comes with various Datastores to store your messages, various LLMs to act as the base of your agentic app. Just define the background data of your Agentic app, your tools and you are good to go!


## Components
Agenix allows users to build agentic apps, there are some key components that users should be familiar with before using Agenix.
1. Agent: Agent is the main component you will be dealing with in your flutter and dart code. It exposes you to the public facing API that allows users to generate response from the LLM. 
2. DataStore: This is how Agenix deals with the data, whether it is to save the data, get an ongoing conversation or to fetch all conversations with the agent. You can use a pre-built datastore like FirebaseDataStore, or you can create a custom implementation. 
3. LLM: A large language model to support the agent. You can use a pre-built model like Gemini or if you have a custom implementation running on the server, you can use that.
4. Tools: Tools are elements that do the work for the agent, if you want the agent to fetch news? Make and register a tool to fetch news from the internet.
5. Tool Registry: Whatever tool you have, don't forget to add them to the registry!


## How to Use?

### Initialization
An agentic app runs using an AI Agent, your AI agent should have some background knowledge about your application and what job is it performing. To provide this knowledge add a file called **system_data.json**, in this file define the name of the agent, it's role in the app, it's personality and anything else you want to add. You can basically customize this file as per your wish.
Location of the file


**assets/system_data.json**


In the main function or in your bloc or the point of contact to your agent, add the following lines to initialize the Agent. This current example initializes the agent using firebase firestore as DataStore and Gemini as the LLM. You can swap them for your own implementations. You can create as many agents as you want, agenix will keep track of them, internally agenix will delegate tasks to the most appropriate agent. Agenix can also engage multiple agents in a chain to perform a sequence of sub tasks.
```
final agent = await Agent.create(
      dataStore: DataStore.firestoreDataStore(),
      llm: LLM.geminiLLM(apiKey: apiKey, modelName: 'gemini-1.5-flash'),
      name: 'General Purpose Agent',
      role: 'This is the main agent for the platform.',
    );
```

Define your key and run:
```
flutter run -d chrome --dart-define=GEMINI_API_KEY=Your-Gemini-Key
```


### Generating Response
To get a response from the Agent, call the agent.generateResponse method.
```
final res = await agent.generateResponse(
    convoId: '1',
    userMessage: userMessage,
);
```


### Building a tool
The Agent will be capable enough to maintain context using previous messages in a conversation, understand and intelligently respond to user's prompt, but to perform any specific action, like hit an API endpoint, or run a database query, you will need to build and register tools.

There are 2 kinds of tools.
1. Tools without parameters.
2. Tools with parameters.

You can build them something like this. 
```
class NewsTool extends Tool {
  NewsTool({required super.name, required super.description});

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));
    final apiResponse = {
      'headline': 'Flutter is Awesome!',
      'details':
          'Flutter 3.0 has been released with amazing features. The latest flutter version is 3.32, check it out!',
    };
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message:
          'Breaking News: ${apiResponse['headline']}. \n${apiResponse['details']}',
      data:
          apiResponse, // The data field is optional you can return data if it is required.
      needsFurtherReasoning:
          true, // Set this to true if the tool needs further reasoning
    );
  }
}
```

The above tool uses no params, but to use a tool with params. Do something like this.
```
class WeatherTool extends Tool {
  WeatherTool({
    required super.name,
    required super.description,
    required super.parameters,
  });

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));
    final apiResponse = {'temperature': 25, 'condition': 'Sunny'};
    final location = params['location'] as String?;

    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message:
          'The weather in $location is ${apiResponse['condition']} with a temperature of ${apiResponse['temperature']}°C.',
    );
  }
}
```

Once you have defined yout tools, register them as follows:
```
ToolRegistry().registerTool(
      NewsTool(
        name: 'news_tool',
        description:
            'This tool should be used if the user asks for news of any sort.',
      ),
    );
ToolRegistry().registerTool(
    WeatherTool(
        name: 'weather_tool',
        description:
            'This tool should be used if the user asks for the weather.',
        parameters: [
          ParamSpec(
            name: 'location',
            type: 'String',
            description: 'The location for which to get the weather.',
            required: true,
          ),
        ],
    ),
);
```

Once a tool is defined and registered Agenix is capable enough to hit them when required, deduce the parameters from the input, or ask for the parameters if they are required. If your tool fails to perform the intended task, you can try adding a more defined description. If a required task falls under the responsibilities of multiple agents, agenix will engage them in a chain and delegate the sub-tasks to the respective agents. Agenix will manage the chain itself and use the output from one agent as the input of the other. 


## Examples
1. [Example of Multi Agent Systems Built Using Agenix](https://github.com/ahmadexe/agenix-examples/tree/main/multi_agent_system)
2. [Basic usage of Agenix](https://github.com/ahmadexe/agenix/tree/main/example)
3. [Using Agenix with Custom Data Store](https://github.com/ahmadexe/agenix-examples/tree/main/custom_data_source_example)


## Visuals

### Multi Agents System
In this example three agents are working together:
1. Orchestrator: The agent that is responsible for communicating with the end user.
2. News Agent: The agent that is responsible for dealing with News API operations.
3. Favourites Agent: The agent that manages user's favourites, marking something as favourite, removing something from favourite or fetching the user favourites!

https://github.com/user-attachments/assets/f79cf6ac-6913-49a7-982a-bd7b975599b7


#### Workflow:


![flow](https://github.com/user-attachments/assets/8ad9f4ac-018a-4092-bf8c-4fc72da81673)



### Agentic App
An agentic app is basically an application that is powered by an AI agent, this AI agent can perform tasks for the user in the platform, using pre defined tools. The following example shows how an agent "Lens" can have a sepcific personality, it can answer questions about the platform, perform tasks using tools, etc.


https://github.com/user-attachments/assets/bcb56da8-4285-4661-af52-ee8dd6f31d08


## Maintainers
- [Muhammad Ahmad](https://github.com/ahmadexe)
