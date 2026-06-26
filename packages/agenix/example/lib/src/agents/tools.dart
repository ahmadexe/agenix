import 'dart:math';

import 'package:agenix/agenix.dart';

/// Pretends to query a knowledge base. Returns canned, deterministic snippets
/// keyed off the query so the demo is reproducible without a network call.
class WebSearchTool extends Tool {
  WebSearchTool()
    : super(
        name: 'web_search',
        description:
            'Search the public web for recent information about a topic. '
            'Returns 3 short snippets with sources.',
        parameters: [
          ParameterSpecification(
            name: 'query',
            type: 'string',
            description: 'The search query.',
            required: true,
          ),
        ],
      );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final q = (params['query'] ?? '').toString();
    final hits = [
      {
        'title': 'State of $q in 2026',
        'snippet':
            'Industry analysts report rapid adoption of $q, with adoption '
            'rising 47% YoY across enterprise pilots.',
        'source': 'techreview.example.com',
      },
      {
        'title': '$q: a practitioner\'s field guide',
        'snippet':
            'Teams shipping $q in production cite three repeating patterns: '
            'small models, tight evaluation loops, and human-in-the-loop QA.',
        'source': 'eng.example.io/blog',
      },
      {
        'title': 'Open benchmarks for $q',
        'snippet':
            'Open-source benchmarks for $q now cover latency, cost, and '
            'multilingual quality across 11 languages.',
        'source': 'arxiv.example.org/abs/2603.0912',
      },
    ];
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: 'Found ${hits.length} results for "$q".',
      data: {'query': q, 'results': hits},
    );
  }
}

/// Pulls a few "telemetry" data points so the analyst has numbers to crunch.
class MarketDataTool extends Tool {
  MarketDataTool()
    : super(
        name: 'market_data',
        description:
            'Fetch a synthetic time series of weekly adoption metrics for a '
            'given topic, returned as a list of numbers.',
        parameters: [
          ParameterSpecification(
            name: 'topic',
            type: 'string',
            description: 'The subject the metrics describe.',
            required: true,
          ),
        ],
      );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final topic = (params['topic'] ?? 'unknown').toString();
    final seed = topic.codeUnits.fold<int>(7, (a, b) => (a + b) & 0xff);
    final rng = Random(seed);
    final series = List.generate(12, (i) => 100 + i * 6 + rng.nextInt(25));
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: 'Fetched 12 weeks of adoption data for $topic.',
      data: {'topic': topic, 'weeks': series},
    );
  }
}

/// A real calculator — the only tool that actually computes from input.
class StatisticsTool extends Tool {
  StatisticsTool()
    : super(
        name: 'statistics',
        description:
            'Compute basic statistics (mean, min, max, growth percent) on a '
            'list of numeric values.',
        parameters: [
          ParameterSpecification(
            name: 'values',
            type: 'array',
            description: 'List of numbers.',
            required: true,
          ),
        ],
      );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final raw = params['values'];
    final nums =
        (raw is List)
            ? raw
                .map((e) => (e is num) ? e.toDouble() : double.tryParse('$e'))
                .whereType<double>()
                .toList()
            : <double>[];
    if (nums.isEmpty) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'No numeric values provided.',
      );
    }
    final mean = nums.reduce((a, b) => a + b) / nums.length;
    final minV = nums.reduce(min);
    final maxV = nums.reduce(max);
    final growth = ((nums.last - nums.first) / nums.first) * 100;
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message:
          'mean=${mean.toStringAsFixed(1)}, '
          'min=${minV.toStringAsFixed(1)}, '
          'max=${maxV.toStringAsFixed(1)}, '
          'growth=${growth.toStringAsFixed(1)}%',
      data: {
        'mean': mean,
        'min': minV,
        'max': maxV,
        'growth_pct': growth,
        'n': nums.length,
      },
    );
  }
}

/// Simulates pulling sentiment headlines for color in the final narrative.
class SentimentTool extends Tool {
  SentimentTool()
    : super(
        name: 'sentiment_scan',
        description:
            'Estimate overall sentiment (positive / mixed / negative) for a '
            'topic across recent discussion.',
        parameters: [
          ParameterSpecification(
            name: 'topic',
            type: 'string',
            description: 'The subject to scan.',
            required: true,
          ),
        ],
      );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final topic = (params['topic'] ?? '').toString();
    final score =
        (topic.codeUnits.fold<int>(0, (a, b) => a + b) % 100) / 100.0;
    final label =
        score > 0.66
            ? 'positive'
            : score > 0.33
            ? 'mixed'
            : 'cautious';
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message:
          'Community sentiment on $topic is $label '
          '(confidence ${(score * 100).toStringAsFixed(0)}%).',
      data: {'topic': topic, 'label': label, 'confidence': score},
    );
  }
}
