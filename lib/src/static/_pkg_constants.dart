/// Default response when LLM fails
const String kLLMResponseOnFailure =
    "I am unable to process your request at the moment. Please try again later";

/// Maximum number of tool→observe→re-prompt iterations per turn.
const int kMaxToolIterations = 5;

/// Maximum number of corrective re-prompts when the LLM returns unparseable output.
const int kMaxParseRetries = 2;

/// Corrective instruction appended on parse-retry turns.
const String kParseRetryInstruction =
    "Your last reply was not valid JSON. Reply with ONLY the JSON object, no prose, no markdown fences.";

/// Maximum depth for agent chain delegation (prevents unbounded recursion).
const int kMaxChainDepth = 5;
