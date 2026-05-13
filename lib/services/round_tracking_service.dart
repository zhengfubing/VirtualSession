import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';

/// 对话轮次追踪服务
/// 参考 Python db/agent_runtime.py
class RoundTrackingService {
  static final RoundTrackingService instance = RoundTrackingService._();
  RoundTrackingService._();

  final _db = DatabaseHelper.instance;
  static const _uuid = Uuid();

  /// 创建一个新的对话轮次，返回 roundId
  Future<String> createRound({
    required String chatId,
    required String modelName,
    bool enableThinking = false,
    String promptSnapshotJson = '{}',
    String currentSenderId = 'empty',
  }) async {
    final roundId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch / 1000;

    await _db.insert('rounds', {
      'id': roundId,
      'chat_id': chatId,
      'status': 'running',
      'model_name': modelName,
      'stream': 1,
      'enable_thinking': enableThinking ? 1 : 0,
      'current_sender_id': currentSenderId,
      'prompt_snapshot_json': promptSnapshotJson,
      'final_answer_message_id': null,
      'final_reasoning': '',
      'error_message': null,
      'started_at': now,
      'ended_at': null,
    });

    return roundId;
  }

  /// 完成一个轮次
  Future<void> finishRound({
    required String roundId,
    required String status,
    String? finalAnswerMessageId,
    String reasoning = '',
    String? errorMessage,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await _db.update(
      'rounds',
      {
        'status': status,
        'ended_at': now,
        'final_answer_message_id': finalAnswerMessageId,
        'final_reasoning': reasoning,
        'error_message': errorMessage,
      },
      where: 'id = ?',
      whereArgs: [roundId],
    );
  }

  /// 添加轮次事件
  Future<void> addEvent({
    required String chatId,
    required String roundId,
    required String kind,
    required String stage,
    required String direction,
    String? modelName,
    String payloadJson = '{}',
    int promptTokens = 0,
    int completionTokens = 0,
  }) async {
    // 获取当前 round 的最大 seq
    final maxSeqResult = await _db.rawQuery(
      'SELECT COALESCE(MAX(seq), 0) + 1 as next_seq FROM round_events WHERE round_id = ?',
      [roundId],
    );
    final seq = maxSeqResult.first['next_seq'] as int;

    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await _db.insert('round_events', {
      'id': _uuid.v4(),
      'chat_id': chatId,
      'round_id': roundId,
      'seq': seq,
      'kind': kind,
      'stage': stage,
      'direction': direction,
      'model_name': modelName,
      'payload_json': payloadJson,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'created_at': now,
    });
  }

  /// 获取 chat 的最新轮次
  Future<Map<String, dynamic>?> getLatestRound(String chatId) async {
    final results = await _db.query(
      'rounds',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'started_at DESC',
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// 获取 chat 的 token 统计（从 round_events 聚合）
  Future<Map<String, int>> getChatTokenStats(String chatId) async {
    final results = await _db.rawQuery(
      '''SELECT COALESCE(SUM(prompt_tokens), 0) as prompt_tokens,
                COALESCE(SUM(completion_tokens), 0) as completion_tokens
         FROM round_events WHERE chat_id = ?''',
      [chatId],
    );
    if (results.isNotEmpty) {
      return {
        'prompt_tokens': results.first['prompt_tokens'] as int,
        'completion_tokens': results.first['completion_tokens'] as int,
      };
    }
    return {'prompt_tokens': 0, 'completion_tokens': 0};
  }
}
