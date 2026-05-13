import 'dart:convert';

/// 时间跨度分析结果
class TimeSpanInfo {
  final DateTime startTime;
  final DateTime endTime;
  final bool isCrossDay;
  final bool hasLargeGap;
  final List<String> autoTags;

  TimeSpanInfo({
    required this.startTime,
    required this.endTime,
    this.isCrossDay = false,
    this.hasLargeGap = false,
    this.autoTags = const [],
  });
}

/// 记忆列表项
class MemoryListItem {
  final String time;
  final String type; // "important_event" | "important_result"
  final String content;

  MemoryListItem({
    required this.time,
    required this.type,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'type': type,
        'content': content,
      };

  factory MemoryListItem.fromJson(Map<String, dynamic> json) {
    return MemoryListItem(
      time: json['time'] ?? '',
      type: json['type'] ?? '',
      content: json['content'] ?? '',
    );
  }
}

/// 记忆提取 Agent 返回结果
class MemoryExtractionResult {
  final String brief;
  final List<MemoryListItem> list;
  final Map<String, dynamic> roleStateSnapshot;
  final List<String> tags;

  MemoryExtractionResult({
    this.brief = '',
    this.list = const [],
    this.roleStateSnapshot = const {},
    this.tags = const [],
  });

  factory MemoryExtractionResult.fromJson(Map<String, dynamic> json) {
    return MemoryExtractionResult(
      brief: json['brief'] ?? '',
      list: (json['list'] as List<dynamic>?)
              ?.map(
                (e) => e is Map<String, dynamic>
                    ? MemoryListItem.fromJson(e)
                    : MemoryListItem(time: '', type: '', content: ''),
              )
              .toList() ??
          [],
      roleStateSnapshot:
          (json['role_state_snapshot'] as Map<String, dynamic>?) ?? {},
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// Solo 记忆
class SoloMemory {
  final String id;
  final String sessionId;
  final String brief;
  final Map<String, dynamic> roleStateSnapshot;
  final List<String> tags;
  final DateTime timeRangeStart;
  final DateTime timeRangeEnd;
  final List<String> sourceSummaryIds;
  final int memoryCount;
  final String mdFilePath;
  final DateTime createdAt;
  final List<MemoryListItem> list;

  SoloMemory({
    required this.id,
    required this.sessionId,
    required this.brief,
    this.roleStateSnapshot = const {},
    this.tags = const [],
    required this.timeRangeStart,
    required this.timeRangeEnd,
    this.sourceSummaryIds = const [],
    this.memoryCount = 0,
    this.mdFilePath = '',
    required this.createdAt,
    this.list = const [],
  });

  factory SoloMemory.fromMap(Map<String, dynamic> map) {
    return SoloMemory(
      id: map['id'] ?? '',
      sessionId: map['session_id'] ?? '',
      brief: map['brief'] ?? '',
      roleStateSnapshot: _safeParseJson(map['role_state_snapshot_json']),
      tags: (map['tags'] as String?)?.split(',').where((t) => t.isNotEmpty).toList() ?? [],
      timeRangeStart: DateTime.fromMillisecondsSinceEpoch(
        (((map['time_range_start'] as num?)?.toDouble() ?? 0) * 1000).toInt(),
      ),
      timeRangeEnd: DateTime.fromMillisecondsSinceEpoch(
        (((map['time_range_end'] as num?)?.toDouble() ?? 0) * 1000).toInt(),
      ),
      sourceSummaryIds: _safeParseJsonList(map['source_summary_ids_json']),
      memoryCount: (map['memory_count'] as num?)?.toInt() ?? 0,
      mdFilePath: map['md_file_path'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (((map['created_at'] as num?)?.toDouble() ?? 0) * 1000).toInt(),
      ),
    );
  }

  static Map<String, dynamic> _safeParseJson(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final parsed = jsonDecode(json);
      return parsed is Map<String, dynamic> ? parsed : {};
    } catch (_) {
      return {};
    }
  }

  static List<String> _safeParseJsonList(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final parsed = jsonDecode(json);
      return parsed is List ? parsed.cast<String>() : [];
    } catch (_) {
      return [];
    }
  }
}
