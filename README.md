# Agenix

<p align="center">
<a href="https://github.com/ahmadexe/agenix"><img src="https://img.shields.io/github/stars/ahmadexe/agenix.svg?style=flat&logo=github&colorB=deeppink&label=stars" alt="Star on Github"></a>
<a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-purple.svg" alt="License: MIT"></a>
</p>

---

A framework to build agentic apps using Flutter & Dart!

---

## Overview

Agenix aims at providing an easy interface to build Agentic apps using Flutter and Dart. 

## Components
Agenix allows users to build agentic apps, there are some key components that users should be familiar with before using Agenix.
1. Agent: Agent is the main component you will be dealing with in your flutter and dart code. It exposes you to the public facing API that allows users to generate response from the LLM. 
2. DataStore: This is how Agenix deals with the data, whether it is to save the data, get an ongoing conversation or to fetch all conversations with the agent. You can use a pre-built datastore like FirebaseDataStore, or you can create a custom implementation. 
3. LLM: A large language model to support the agent. You can use a pre-built model like Gemini or if you have a custom implementation running on the server, you can use that.
4. Tools: Tools are elements that do the work for the agent, if you want the agent to fetch news? Make and register a tool to fetch news from the internet.

## Maintainers

- [Muhammad Ahmad](https://github.com/ahmadexe)
