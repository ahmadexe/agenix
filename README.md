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

Agenix aims at providing an easy interface to build Agentic apps using Flutter and Dart. It comes with various Datastores to store your messages, various LLMs to act as the base of your agentic app. Just define the data of your Agentic app, your tools and you are good to go!

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


In the main function or in your bloc or the point of contact to your agent, add the following lines to initialize the Agent.
```
final agent = Agent();
agent.init(
    dataStore: YourDataStore(),
    llm: YourLLM(),
);
```

If you want to use Firebase Firestore as your DataStore, and Gemini as your LLM, you can do something like this:
```
final agent = Agent();
const apiKey = String.fromEnvironment('GEMINI_API_KEY');
agent.init(
    dataStore: DataStore.firestoreDataStore(),
    llm: LLM.geminiLLM(apiKey: apiKey, modelName: 'gemini-1.5-flash'),
);
```

Run and define your key:
```
flutter run -d chrome --dart-define=GEMINI_API_KEY=Your-Gemini-Key
```

### Generating Response
To get a response from the Agent, call the agent.generateResponse method.
```
final res = await Agent().generateResponse(
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
  Future<Map<String, dynamic>?> run(Map<String, dynamic> params) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));
    return {
      'title': 'Breaking News',
      'description': 'This is a sample news description.',
    };  
  }
}
```

The above tool uses no params, but to use a tool with params. Do something like this.
```
class WeatherTool extends Tool {
  WeatherTool({required super.name, required super.description, required super.parameters});

  @override
  Future<Map<String, dynamic>?> run(Map<String, dynamic> params) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));
    return {
      'temperature': '25°C',
      'condition': 'Sunny',
      'location': params['location'],
    };
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

Once a tool is defined Agenix is capable enough to hit them when required, deduce the parameters from the input, or ask for the parameters if they are required. If your tool fails to perform the intended task, you can try adding a more defined description.

## Examples
To view full feldg examples, please take a look inside the example directory!

## Maintainers

- [Muhammad Ahmad](https://github.com/ahmadexe)
