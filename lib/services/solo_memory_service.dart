import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/ai_model.dart';
import '../models/solo_memory.dart';
import 'ai_service.dart';
import 'app_config_service.dart';
import 'file_storage_service.dart';

/// 记忆提取 Agent 的 System Prompt
const _memoryExtractionPrompt = '''你是记忆提取器。输入是连续 N 轮对话的压缩摘要（JSON 数组）。
请基于这些摘要，提取结构化记忆。

要求：
1. 只基于输入，不得添加新事实
2. brief 是一句话概括这 N 轮摘要的核心内容（用于替换上下文中的摘要）
3. list 是重要事件/结果列表，每个元素必须包含：
   - time: 发生时间（如果输入中没有精确时间，从摘要的 created_at 推算）
   - type: "important_event" 或 "important_result"
   - content: 一句话描述
4. role_state_snapshot 是角色当前状态快照，格式：
   {role_name: {mood, location, status, goals}}

时间判定规则（会由系统预先分析并告知）：
- 如果这些摘要跨越了多个自然日 → 打上 cross_day 标签
- 如果对话中有明确的重要事件（决定、转折、信息获取）→ 打上 important_event 标签
- 如果对话产生了明确结果（任务完成、问题解决、关系变化）→ 打上 important_result 标签
- 如果时间无明显特殊性且无重要事项 → list 可以只有一个元素，一句话概括全部

返回 JSON 对象，字段必须包含：
- brief: string
- list: [{time: string, type: string, content: string}]
- role_state_snapshot: {string: {mood?: string, location?: string, status?: string, goals?: string[]}}
- tags: string[]

不要输出 JSON 以外内容。''';

class SoloMemoryService {
  static final SoloMemoryService instance = SoloMemoryService._();
  SoloMemoryService._();

  final _db = DatabaseHelper.instance;
  final _fileStorage = FileStorageService();
  static const _uuid = Uuid();

  /// 防并发提取锁
  final Set<String> _extractingSessions = {};

  // ==================== 记忆提取 ====================

  /// 检查是否需要提取记忆，如果需要则执行
  Future<void> checkAndExtract({required String sessionId}) async {
    if (_extractingSessions.contains(sessionId)) return;
    _extractingSessions.add(sessionId);
    try {
      await _doCheckAndExtract(sessionId: sessionId);
    } finally {
      _extractingSessions.remove(sessionId);
    }
  }

  Future<void> _doCheckAndExtract({required String sessionId}) async {
    final cfg = AppConfigService.instance;
    final memoryRounds = cfg.soloMemoryRounds;
    final recentKeep = cfg.soloMemoryRecentKeep;

    // 1. 查询活跃摘要中未被记忆消费的数量
    final activeSummaries = await _db.query(
      'summaries',
      where: 'chat_id = ? AND status = ? AND memory_id IS NULL',
      whereArgs: [sessionId, 'active'],
      orderBy: 'created_at ASC',
    );

    // 2. 数量不够则跳过
    if (activeSummaries.length < memoryRounds) return;

    // 3. 保留最近 recentKeep 条不消费
    final consumable = activeSummaries.length - recentKeep;
    if (consumable < memoryRounds) return;

    // 4. 取最老的 memoryRounds 条进行记忆提取
    final source = activeSummaries.sublist(0, memoryRounds);

    // 5. 执行提取
    await extractMemory(sessionId: sessionId, sourceSummaries: source);

    // 6. 防止记忆膨胀
    await _trimMemoryRefs(sessionId);
  }

  /// 执行一次记忆提取
  Future<SoloMemory?> extractMemory({
    required String sessionId,
    required List<Map<String, dynamic>> sourceSummaries,
  }) async {
    // 1. 分析时间跨度
    final timeSpan = _analyzeTimeSpan(sourceSummaries);

    // 2. 获取记忆提取模型
    final modelName = AppConfigService.instance.soloMemoryModel;
    final modelMap = await _db.getModelByName(modelName);
    if (modelMap == null) return null;
    final model = AIModel.fromMap(modelMap);

    // 3. 调用记忆提取 Agent
    final result = await _callMemoryAgent(
      summaries: sourceSummaries,
      timeSpan: timeSpan,
      model: model,
    );
    if (result.brief.isEmpty) return null;

    // 4. 生成 memory_id
    final memoryId = 'mem_${_uuid.v4().substring(0, 12)}';

    // 5. 构建完整 JSON 数据
    final allTags = [...result.tags, ...timeSpan.autoTags];
    final sourceSummaryIds = sourceSummaries.map((s) => s['id'] as String).toList();
    final fullData = {
      'memory_id': memoryId,
      'brief': result.brief,
      'list': result.list.map((e) => e.toJson()).toList(),
      'role_state_snapshot': result.roleStateSnapshot,
      'tags': allTags,
      'source_summary_ids': sourceSummaryIds,
      'time_range': {
        'start': timeSpan.startTime.toIso8601String(),
        'end': timeSpan.endTime.toIso8601String(),
      },
      'created_at': DateTime.now().toIso8601String(),
    };

    // 6. 写入 SQLite（权威源，先写）
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final memoryCount = await _getNextMemoryCount(sessionId);
    final mdPath = 'memories/$memoryId.md';

    await _db.insert('solo_memories', {
      'id': memoryId,
      'session_id': sessionId,
      'brief': result.brief,
      'role_state_snapshot_json': jsonEncode(result.roleStateSnapshot),
      'tags': allTags.join(','),
      'time_range_start': timeSpan.startTime.millisecondsSinceEpoch / 1000,
      'time_range_end': timeSpan.endTime.millisecondsSinceEpoch / 1000,
      'source_summary_ids_json': jsonEncode(sourceSummaryIds),
      'memory_count': memoryCount,
      'md_file_path': mdPath,
      'created_at': now,
    });

    // 7. 写入 MD 文件（失败不影响一致性，可从 SQLite 重建）
    try {
      await _writeMdFile(memoryId, fullData);
    } catch (_) {}

    // 8. 标记被消费的摘要
    for (final sid in sourceSummaryIds) {
      await _db.update(
        'summaries',
        {'memory_id': memoryId, 'status': 'archived'},
        where: 'id = ?',
        whereArgs: [sid],
      );
    }

    // 9. 替换 context_items
    final summaryRefIds = await _getSummaryRefIds(sourceSummaryIds);
    await _replaceSummariesWithMemory(
      sessionId: sessionId,
      memoryId: memoryId,
      brief: result.brief,
      consumedSummaryItemIds: summaryRefIds,
    );

    return SoloMemory(
      id: memoryId,
      sessionId: sessionId,
      brief: result.brief,
      roleStateSnapshot: result.roleStateSnapshot,
      tags: allTags,
      timeRangeStart: timeSpan.startTime,
      timeRangeEnd: timeSpan.endTime,
      sourceSummaryIds: sourceSummaryIds,
      memoryCount: memoryCount,
      mdFilePath: mdPath,
      createdAt: DateTime.now(),
      list: result.list,
    );
  }

  // ==================== 记忆检索 ====================

  Future<String?> getMemoryDetail(String memoryId) async {
    return await _fileStorage.readMemory(memoryId);
  }

  Future<Map<String, dynamic>?> getMemoryBrief(String memoryId) async {
    final results = await _db.query(
      'solo_memories',
      where: 'id = ?',
      whereArgs: [memoryId],
    );
    if (results.isEmpty) return null;
    final r = results.first;
    return {
      'id': r['id'],
      'brief': r['brief'],
      'tags': r['tags'],
      'role_state_snapshot': _safeParseJsonMap(r['role_state_snapshot_json']),
      'time_range_start': r['time_range_start'],
      'time_range_end': r['time_range_end'],
      'created_at': r['created_at'],
    };
  }

  Future<List<Map<String, dynamic>>> listMemories(String sessionId) async {
    return await _db.query(
      'solo_memories',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
    );
  }

  // ==================== Agent 工具定义 ====================

  /// 获取记忆工具定义列表（用于注册到 Agent 的 tools 参数）
  static List<Map<String, dynamic>> getMemoryToolDefinitions() {
    return [
      {
        'type': 'function',
        'function': {
          'name': 'get_memory_detail',
          'description': '获取记忆的完整详细内容。当需要回忆过去对话的具体细节时调用。',
          'parameters': {
            'type': 'object',
            'properties': {
              'memory_id': {
                'type': 'string',
                'description': '记忆 ID，从上下文的 memory_context 消息中获取',
              },
            },
            'required': ['memory_id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'get_memory_brief',
          'description': '获取记忆的简要摘要。当需要快速浏览历史记忆时调用。',
          'parameters': {
            'type': 'object',
            'properties': {
              'memory_id': {
                'type': 'string',
                'description': '记忆 ID，从上下文的 memory_context 消息中获取',
              },
            },
            'required': ['memory_id'],
          },
        },
      },
    ];
  }

  /// 执行记忆工具调用
  /// 返回 tool 消息的 JSON 字符串
  Future<String?> executeMemoryTool(String toolName, Map<String, dynamic> arguments) async {
    final memoryId = arguments['memory_id'] as String?;
    if (memoryId == null || memoryId.isEmpty) {
      return jsonEncode({
        'role': 'tool',
        'tool_call_id': arguments['tool_call_id'] ?? '',
        'content': jsonEncode({'error': 'memory_id is required'}),
      });
    }

    switch (toolName) {
      case 'get_memory_detail':
        final detail = await getMemoryDetail(memoryId);
        return jsonEncode({
          'role': 'tool',
          'tool_call_id': arguments['tool_call_id'] ?? '',
          'content': detail ?? 'Memory not found: $memoryId',
        });
      case 'get_memory_brief':
        final brief = await getMemoryBrief(memoryId);
        return jsonEncode({
          'role': 'tool',
          'tool_call_id': arguments['tool_call_id'] ?? '',
          'content': brief != null ? jsonEncode(brief) : 'Memory not found: $memoryId',
        });
      default:
        return jsonEncode({
          'role': 'tool',
          'tool_call_id': arguments['tool_call_id'] ?? '',
          'content': jsonEncode({'error': 'Unknown tool: $toolName'}),
        });
    }
  }

  // ==================== 内部方法 ====================

  TimeSpanInfo _analyzeTimeSpan(List<Map<String, dynamic>> summaries) {
    final times = summaries
        .map((s) => DateTime.fromMillisecondsSinceEpoch(
              (((s['created_at'] as num?)?.toDouble() ?? 0) * 1000).toInt(),
            ))
        .toList()
      ..sort();

    final start = times.first;
    final end = times.last;

    final isCrossDay = start.year != end.year ||
        start.month != end.month ||
        start.day != end.day;

    var hasLargeGap = false;
    for (var i = 1; i < times.length; i++) {
      if (times[i].difference(times[i - 1]).inHours >= 6) {
        hasLargeGap = true;
        break;
      }
    }

    final autoTags = <String>[];
    if (isCrossDay) autoTags.add('cross_day');
    if (hasLargeGap) autoTags.add('large_time_gap');

    return TimeSpanInfo(
      startTime: start,
      endTime: end,
      isCrossDay: isCrossDay,
      hasLargeGap: hasLargeGap,
      autoTags: autoTags,
    );
  }

  Future<MemoryExtractionResult> _callMemoryAgent({
    required List<Map<String, dynamic>> summaries,
    required TimeSpanInfo timeSpan,
    required AIModel model,
  }) async {
    final req = _buildMemoryExtractionRequest(
      summaries: summaries,
      timeSpan: timeSpan,
    );

    try {
      final result = await AIService.chatCompletion(
        model: model,
        messages: req['messages'] as List<String>,
        systemPrompt: req['system_prompt'] as String,
        extraBody: {'enable_thinking': false},
      );

      final data = _safeParseJson(result.answer);
      if (data is Map<String, dynamic>) {
        return MemoryExtractionResult.fromJson(data);
      }
      return MemoryExtractionResult();
    } catch (_) {
      return MemoryExtractionResult();
    }
  }

  Map<String, dynamic> _buildMemoryExtractionRequest({
    required List<Map<String, dynamic>> summaries,
    required TimeSpanInfo timeSpan,
  }) {
    final summaryTexts = summaries.map((s) => jsonEncode({
      'summary_id': s['id'],
      'summary_text': s['summary_text'],
      'facts': _parseJsonField(s['facts_json']),
      'decisions': _parseJsonField(s['decisions_json']),
      'role_state': _parseJsonField(s['role_state_json']),
      'created_at': s['created_at'],
    })).toList();

    final timeContext = '时间上下文：\n'
        '- 起始时间：${timeSpan.startTime}\n'
        '- 结束时间：${timeSpan.endTime}\n'
        '- 是否跨天：${timeSpan.isCrossDay}\n'
        '- 大时间间隔：${timeSpan.hasLargeGap}\n'
        '- 系统自动标签：${timeSpan.autoTags.join(', ')}\n';

    final payload = jsonEncode({
      'time_context': timeContext,
      'summaries': summaryTexts,
    });

    return {
      'system_prompt': _memoryExtractionPrompt,
      'messages': [
        jsonEncode({'role': 'user', 'content': payload}),
      ],
    };
  }

  Future<String> _writeMdFile(String memoryId, Map<String, dynamic> fullData) async {
    final timeRange = fullData['time_range'] as Map<String, dynamic>? ?? {};
    final tags = (fullData['tags'] as List<dynamic>?)?.join(', ') ?? '';
    final brief = fullData['brief'] ?? '';
    final list = fullData['list'] as List<dynamic>? ?? [];
    final roleState = fullData['role_state_snapshot'] as Map<String, dynamic>? ?? {};

    // 构建 Markdown 表格内容
    final tableHeader = '| 时间 | 类型 | 内容 |\n|------|------|------|';
    final tableRows = list.map((item) {
      final m = item as Map<String, dynamic>;
      return '| ${m['time'] ?? ''} | ${m['type'] ?? ''} | ${m['content'] ?? ''} |';
    }).join('\n');

    // 构建角色状态
    final roleStateLines = roleState.entries.map((e) {
      final v = e.value is Map ? e.value as Map<String, dynamic> : <String, dynamic>{};
      final parts = <String>[];
      if (v['mood'] != null) parts.add(v['mood'].toString());
      if (v['location'] != null) parts.add(v['location'].toString());
      if (v['status'] != null) parts.add(v['status'].toString());
      final extra = parts.isNotEmpty ? '（${parts.join('、')}）' : '';
      return '- ${e.key}$extra';
    }).join('\n');

    final content = '''# 记忆 $memoryId

**时间范围**：${timeRange['start'] ?? ''} ~ ${timeRange['end'] ?? ''}
**标签**：$tags

---

## 简要概括

$brief

## 重要事件

$tableHeader
$tableRows

## 角色状态

$roleStateLines

## 原始数据

```json
${const JsonEncoder.withIndent('  ').convert(fullData)}
```
''';

    await _fileStorage.saveMemory(memoryId, content);
    return 'memories/$memoryId.md';
  }

  Future<void> _replaceSummariesWithMemory({
    required String sessionId,
    required String memoryId,
    required String brief,
    required List<String> consumedSummaryItemIds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;

    // 1. 停用旧的 summary_ref context_items
    for (final id in consumedSummaryItemIds) {
      await _db.update(
        'context_items',
        {'active': 0},
        where: 'id = ? AND chat_id = ?',
        whereArgs: [id, sessionId],
      );
    }

    // 2. 获取最大 seq
    final maxSeqResult = await _db.rawQuery(
      'SELECT COALESCE(MAX(seq), 0) + 1 as next_seq FROM context_items WHERE chat_id = ?',
      [sessionId],
    );
    final seq = maxSeqResult.first['next_seq'] as int;

    // 3. 插入 memory_ref
    final content = jsonEncode({
      'memory_id': memoryId,
      'brief': brief,
    });

    await _db.insert('context_items', {
      'id': _uuid.v4(),
      'chat_id': sessionId,
      'seq': seq,
      'item_type': 'memory_ref',
      'role': 'system',
      'content': content,
      'priority': 'high',
      'compressible': 0,
      'active': 1,
      'created_at': now,
    });
  }

  Future<void> _trimMemoryRefs(String sessionId) async {
    final maxContext = AppConfigService.instance.soloMemoryMaxContext;
    final allMemoryRefs = await _db.query(
      'context_items',
      where: 'chat_id = ? AND item_type = ? AND active = 1',
      whereArgs: [sessionId, 'memory_ref'],
      orderBy: 'created_at ASC',
    );
    if (allMemoryRefs.length <= maxContext) return;

    final toDeactivate = allMemoryRefs.sublist(0, allMemoryRefs.length - maxContext);
    for (final item in toDeactivate) {
      await _db.update(
        'context_items',
        {'active': 0},
        where: 'id = ?',
        whereArgs: [item['id']],
      );
    }
  }

  Future<int> _getNextMemoryCount(String sessionId) async {
    final result = await _db.rawQuery(
      'SELECT COALESCE(MAX(memory_count), 0) + 1 as next_count FROM solo_memories WHERE session_id = ?',
      [sessionId],
    );
    return (result.first['next_count'] as num?)?.toInt() ?? 1;
  }

  /// 根据 summary IDs 找到对应的 summary_ref context_items
  Future<List<String>> _getSummaryRefIds(List<String> summaryIds) async {
    if (summaryIds.isEmpty) return [];
    final refIds = <String>[];
    for (final sid in summaryIds) {
      final rows = await _db.query(
        'summaries',
        where: 'id = ?',
        whereArgs: [sid],
      );
      if (rows.isNotEmpty && rows.first['context_item_id'] != null) {
        refIds.add(rows.first['context_item_id'] as String);
      }
    }
    return refIds;
  }

  // ==================== 辅助方法 ====================

  dynamic _parseJsonField(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return jsonDecode(json);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _safeParseJsonMap(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final parsed = jsonDecode(json);
      return parsed is Map<String, dynamic> ? parsed : {};
    } catch (_) {
      return {};
    }
  }

  dynamic _safeParseJson(String text) {
    var s = text.trim();
    if (s.startsWith('```json')) s = s.substring(7);
    if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    s = s.trim();
    if (s.isEmpty) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
}
