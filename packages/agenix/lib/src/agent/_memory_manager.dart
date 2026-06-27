// Internal file, not part of the Public API

part of 'agent.dart';

class _MemoryManager {
  final DataStore dataStore;
  final LLM _llm;

  // 0 means summarization is disabled — evicted messages are simply dropped.
  final int _summarizationBatchSize;

  // Per-conversation state (in-process memory only, never persisted).
  final Map<String, int> _savedCount = {};
  final Map<String, int> _evictionCursor = {};
  final Map<String, List<AgentMessage>> _pendingBatch = {};
  final Map<String, String> _rollingContext = {};

  _MemoryManager({
    required this.dataStore,
    required LLM llm,
    required int summarizationBatchSize,
  })  : _llm = llm,
        _summarizationBatchSize = summarizationBatchSize;

  Future<void> saveMessage(
    String convoId,
    AgentMessage msg, {
    Object? metaData,
  }) async {
    await dataStore.saveMessage(convoId, msg, metaData: metaData);
    _savedCount[convoId] = (_savedCount[convoId] ?? 0) + 1;
  }

  /// Returns the active context window and any rolling summary of evicted history.
  ///
  /// When [_summarizationBatchSize] is 0, evicted messages are discarded and
  /// [summary] is always null. When set, evicted messages accumulate in a batch;
  /// once the batch reaches the threshold the LLM summarizes them and the result
  /// is returned as [summary] to be prepended to the prompt.
  Future<({List<AgentMessage> messages, String? summary})> getContext(
    String convoId, {
    int? limit,
    Object? metaData,
  }) async {
    if (_summarizationBatchSize == 0 || limit == null) {
      final msgs = await dataStore.getMessages(
        convoId,
        limit: limit,
        metaData: metaData,
      );
      return (messages: msgs, summary: _rollingContext[convoId]);
    }

    final totalSaved = _savedCount[convoId] ?? 0;
    final evictedZoneEnd = (totalSaved - limit).clamp(0, totalSaved);
    final cursor = _evictionCursor[convoId] ?? 0;

    if (evictedZoneEnd > cursor) {
      // Bounded fetch: covers [cursor..totalSaved) — no full-history read.
      final fetchCount = totalSaved - cursor;
      final fromCursor = await dataStore.getMessages(
        convoId,
        limit: fetchCount,
        metaData: metaData,
      );

      final newlyEvictedCount = evictedZoneEnd - cursor;
      final newlyEvicted = fromCursor
          .take(newlyEvictedCount)
          .where((m) => !m.isError)
          .toList();

      _evictionCursor[convoId] = evictedZoneEnd;

      if (newlyEvicted.isNotEmpty) {
        (_pendingBatch[convoId] ??= []).addAll(newlyEvicted);
        await _maybeSummarize(convoId);
      }

      final active = fromCursor.skip(newlyEvictedCount).toList();
      return (messages: active, summary: _rollingContext[convoId]);
    }

    // No new evictions: bounded active-window fetch only.
    final active = await dataStore.getMessages(
      convoId,
      limit: limit,
      metaData: metaData,
    );
    return (messages: active, summary: _rollingContext[convoId]);
  }

  Future<void> _maybeSummarize(String convoId) async {
    final batch = _pendingBatch[convoId];
    if (batch == null || batch.length < _summarizationBatchSize) return;

    final toSummarize = List<AgentMessage>.of(batch);
    _pendingBatch[convoId] = [];

    final historyText = toSummarize
        .map((m) => '${m.isFromAgent ? 'Assistant' : 'User'}: ${m.content}')
        .join('\n');

    final existing = _rollingContext[convoId];
    final prompt = existing != null
        ? 'You have an existing summary of an earlier conversation:\n$existing\n\n'
          'Extend it by incorporating these newer messages into one updated concise summary:\n$historyText'
        : 'Summarize the following conversation messages into one concise paragraph '
          'that preserves key facts, context, and decisions for future reference:\n\n'
          '$historyText';

    try {
      final result = await _llm.generate(prompt: prompt);
      _rollingContext[convoId] = result.trim();
    } catch (_) {
      // Summarization failed — restore the batch so messages are not lost.
      _pendingBatch[convoId] = [...toSummarize, ..._pendingBatch[convoId]!];
    }
  }
}
