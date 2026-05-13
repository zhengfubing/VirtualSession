import 'dart:convert';

/// 上下文构建服务
/// 从 context_history + summary_history 构建发送给 LLM 的消息列表
class ContextBuilderService {
  static final ContextBuilderService instance = ContextBuilderService._();
  ContextBuilderService._();

  /// 构建有效上下文
  ///
  /// 注入顺序：
  /// 1. memory_ref 项（最前，被动注入记忆上下文）
  /// 2. 未被记忆消费的活跃摘要（priority: high）
  /// 3. 未被摘要覆盖的原始消息（取最后 recentKeep 条）
  ///
  /// 返回: JSON 字符串列表，每个元素格式: '{"role":"user","content":"..."}'
  List<String> buildEffectiveContext({
    required Map<String, dynamic> chatState,
    int recentKeep = 12,
  }) {
    final contextHistory =
        (chatState['context_history'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
    final summaryHistory =
        (chatState['summary_history'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();

    final blocks = <Map<String, dynamic>>[];

    // 1. memory_ref 项（被动注入模式，不依赖 Function Calling）
    final memoryRefs = contextHistory
        .where((m) => (m['type'] ?? m['item_type'] ?? '') == 'memory_ref')
        .toList();
    for (final ref in memoryRefs) {
      blocks.add({
        'messages': [_memoryRefToContextMessage(ref)],
        'priority': 'high',
        'source': 'memory',
      });
    }

    // 2. 活跃摘要（仅加载未被记忆消费的）
    final activeSummaries =
        summaryHistory
            .where((s) =>
                (s['status'] ?? 'active') == 'active' &&
                (s['memory_id'] == null || (s['memory_id'] as String).isEmpty))
            .toList()
          ..sort(
            (a, b) => ((a['created_at'] ?? 0) as num).compareTo(
              (b['created_at'] ?? 0) as num,
            ),
          );

    for (var s in activeSummaries) {
      blocks.add({
        'messages': [_summaryToContextMessage(s)],
        'priority': 'high',
        'source': 'summary',
      });
    }

    // 被摘要覆盖的消息 ID 集合
    final coveredIds = _extractCoveredIds(activeSummaries);

    // 未被覆盖的原始消息
    final rawMessages =
        contextHistory
            .where(
              (m) =>
                  (m['type'] ?? m['item_type'] ?? 'message') == 'message' &&
                  !coveredIds.contains(m['id']),
            )
            .toList()
          ..sort(
            (a, b) =>
                ((a['seq'] ?? 0) as num).compareTo((b['seq'] ?? 0) as num),
          );

    // 取最后 recentKeep 条
    final tail = rawMessages.length > recentKeep
        ? rawMessages.sublist(rawMessages.length - recentKeep)
        : rawMessages;

    // 构建 raw blocks
    blocks.addAll(_buildRawBlocks(tail));

    // 展平
    return _flattenBlocks(blocks);
  }

  /// memory_ref 转为上下文消息
  /// 返回 JSON 字符串: '{"role":"system","content":"..."}'
  String _memoryRefToContextMessage(Map<String, dynamic> item) {
    Map<String, dynamic> contentObj;
    try {
      contentObj = jsonDecode(item['content'] ?? '{}');
    } catch (_) {
      contentObj = {};
    }
    final obj = <String, dynamic>{
      'type': 'memory_context',
      'memory_id': contentObj['memory_id'] ?? '',
      'brief': contentObj['brief'] ?? '',
      'available_detail': true,
    };
    return jsonEncode({'role': 'system', 'content': jsonEncode(obj)});
  }

  /// 摘要转为 context 消息
  /// 返回 JSON 字符串: '{"role":"system","content":"..."}'
  String _summaryToContextMessage(Map<String, dynamic> s) {
    final summaryObj = <String, dynamic>{
      'type': 'summary',
      'summary_text': s['summary_text'] ?? '',
    };

    final facts = _parseJsonList(s['facts'] ?? s['facts_json']);
    if (facts.isNotEmpty) {
      summaryObj['facts'] = facts;
    }

    final decisions = _parseJsonList(s['decisions'] ?? s['decisions_json']);
    if (decisions.isNotEmpty) {
      summaryObj['decisions'] = decisions;
    }

    final roleState = _parseJsonList(s['role_state'] ?? s['role_state_json']);
    if (roleState.isNotEmpty) {
      summaryObj['role_state'] = roleState;
    }

    return jsonEncode({'role': 'system', 'content': jsonEncode(summaryObj)});
  }

  List<dynamic> _parseJsonList(dynamic value) {
    if (value is List) return value;
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    return [];
  }

  /// 提取被摘要覆盖的消息 ID
  Set<String> _extractCoveredIds(List<Map<String, dynamic>> summaries) {
    final ids = <String>{};
    for (var s in summaries) {
      final sourceIds = s['source_message_ids'];
      if (sourceIds is List) {
        ids.addAll(sourceIds.map((e) => e.toString()));
      }
      // 也尝试解析 JSON 字符串
      final sourceIdsJson = s['source_message_ids_json'] as String?;
      if (sourceIdsJson != null && sourceIdsJson.isNotEmpty) {
        try {
          final parsed = jsonDecode(sourceIdsJson);
          if (parsed is List) {
            ids.addAll(parsed.map((e) => e.toString()));
          }
        } catch (_) {}
      }
    }
    return ids;
  }

  /// 构建 raw blocks（合并 tool_calls + tool 结果为同一块）
  List<Map<String, dynamic>> _buildRawBlocks(List<Map<String, dynamic>> items) {
    final blocks = <Map<String, dynamic>>[];
    var i = 0;
    while (i < items.length) {
      final item = items[i];
      final role = item['role'] ?? '';
      final priority = item['priority'] ?? 'normal';

      // tool_calls 消息 + 后续 tool 结果合并为一个块
      if (role == 'assistant' && item['tool_calls'] != null) {
        final chain = [_toApiMessage(item)];
        final toolCallIds = <String>{};
        if (item['tool_calls'] is List) {
          for (var tc in item['tool_calls'] as List) {
            if (tc is Map && tc['id'] != null) {
              toolCallIds.add(tc['id'].toString());
            }
          }
        }
        var j = i + 1;
        while (j < items.length) {
          final next = items[j];
          if (next['role'] != 'tool') break;
          final tcId = next['tool_call_id']?.toString() ?? '';
          if (tcId.isNotEmpty && !toolCallIds.contains(tcId)) break;
          chain.add(_toApiMessage(next));
          j++;
        }
        blocks.add({'messages': chain, 'priority': priority, 'source': 'raw'});
        i = j;
        continue;
      }

      blocks.add({
        'messages': [_toApiMessage(item)],
        'priority': priority,
        'source': 'raw',
      });
      i++;
    }
    return blocks;
  }

  /// 转为 API 消息格式
  /// 返回 JSON 字符串: '{"role":"user","content":"..."}'
  String _toApiMessage(Map<String, dynamic> item) {
    final role = item['role'] ?? 'user';
    var content = item['content'] ?? '';

    // 如果 content 是 JSON 字符串（如 UserMessageContent 的序列化），
    // 尝试提取其中的 message_content 作为纯文本
    if (content is String && content.isNotEmpty) {
      if (content.startsWith('{') && content.contains('message_content')) {
        try {
          final decoded = jsonDecode(content) as Map<String, dynamic>;
          final msgContent = decoded['message_content'];
          if (msgContent is String) {
            content = msgContent;
          }
        } catch (_) {
          // 解析失败，保持原样
        }
      }
    }

    final msg = <String, dynamic>{'role': role, 'content': content};
    if (role == 'assistant' && item['tool_calls'] != null) {
      msg['tool_calls'] = item['tool_calls'];
    }
    if (role == 'tool') {
      if (item['tool_call_id'] != null) {
        msg['tool_call_id'] = item['tool_call_id'];
      }
      if (item['name'] != null) {
        msg['name'] = item['name'];
      }
    }
    return jsonEncode(msg);
  }

  /// 展平 blocks 为 JSON 字符串消息列表
  List<String> _flattenBlocks(List<Map<String, dynamic>> blocks) {
    final out = <String>[];
    for (var block in blocks) {
      final msgs = block['messages'] as List<dynamic>?;
      if (msgs != null) {
        out.addAll(msgs.cast<String>());
      }
    }
    return out;
  }
}
