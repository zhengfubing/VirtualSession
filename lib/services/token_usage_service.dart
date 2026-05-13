import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';

/// Token 使用统计服务
/// 参考 Python db/usage.py
class TokenUsageService {
  static final TokenUsageService instance = TokenUsageService._();
  TokenUsageService._();

  final _db = DatabaseHelper.instance;
  static const _uuid = Uuid();

  /// 记录一次 token 消耗（写入 events + upsert totals）
  Future<void> addTokenUsage({
    required String chatId,
    required String agentType,
    int promptTokens = 0,
    int completionTokens = 0,
    String? roundId,
    String? modelName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;

    // 写入事件
    await _db.insert('token_usage_events', {
      'chat_id': chatId,
      'round_id': roundId,
      'agent_type': agentType,
      'model_name': modelName,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'created_at': now,
    });

    // Upsert 累计统计
    final existing = await _db.query(
      'token_usage_totals',
      where: 'chat_id = ? AND agent_type = ?',
      whereArgs: [chatId, agentType],
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      await _db.update(
        'token_usage_totals',
        {
          'prompt_tokens': (row['prompt_tokens'] as int) + promptTokens,
          'completion_tokens':
              (row['completion_tokens'] as int) + completionTokens,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    } else {
      await _db.insert('token_usage_totals', {
        'id': _uuid.v4(),
        'chat_id': chatId,
        'agent_type': agentType,
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'updated_at': now,
      });
    }
  }

  /// 获取指定 chat 的 token 使用统计
  Future<Map<String, Map<String, int>>> getTokenUsageStats(
      String chatId) async {
    final rows = await _db.query(
      'token_usage_totals',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );

    final result = <String, Map<String, int>>{
      'chat_agent': {'prompt_tokens': 0, 'completion_tokens': 0},
      'tool_agent': {'prompt_tokens': 0, 'completion_tokens': 0},
      'world_chat_agent': {'prompt_tokens': 0, 'completion_tokens': 0},
      'compression_agent': {'prompt_tokens': 0, 'completion_tokens': 0},
    };

    for (var row in rows) {
      final agentType = row['agent_type'] as String;
      result[agentType] = {
        'prompt_tokens': row['prompt_tokens'] as int,
        'completion_tokens': row['completion_tokens'] as int,
      };
    }

    return result;
  }
}
