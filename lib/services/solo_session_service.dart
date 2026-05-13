import '../database/database_helper.dart';
import 'chat_state_service.dart';

class SoloSessionService {
  static final SoloSessionService instance = SoloSessionService._();
  SoloSessionService._();

  final _db = DatabaseHelper.instance;

  /// 根据 AI 角色名获取或创建会话
  Future<Map<String, dynamic>> getOrCreateSession({
    required String aiRoleName,
    required String userRoleName,
    String scenePromptId = 'empty',
  }) async {
    final existing = await getSession(aiRoleName);
    if (existing != null) {
      // 更新 updated_at
      await _db.update(
        'solo_sessions',
        {'updated_at': DateTime.now().millisecondsSinceEpoch / 1000},
        where: 'id = ?',
        whereArgs: [existing['id']],
      );
      return existing;
    }
    return await _createSession(
      aiRoleName: aiRoleName,
      userRoleName: userRoleName,
      scenePromptId: scenePromptId,
    );
  }

  Future<Map<String, dynamic>> _createSession({
    required String aiRoleName,
    required String userRoleName,
    String scenePromptId = 'empty',
  }) async {
    final sessionId = aiRoleName.replaceAll('.md', '');
    final now = DateTime.now().millisecondsSinceEpoch / 1000;

    await _db.insert('solo_sessions', {
      'id': sessionId,
      'ai_role_name': aiRoleName.replaceAll('.md', ''),
      'user_role_name': userRoleName.replaceAll('.md', ''),
      'scene_prompt_id': scenePromptId,
      'status': 'active',
      'system_prompt_json': '{}',
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    });

    return (await getSession(aiRoleName))!;
  }

  /// 获取某个 AI 角色的会话
  Future<Map<String, dynamic>?> getSession(String aiRoleName) async {
    final sessionId = aiRoleName.replaceAll('.md', '');
    final results = await _db.query(
      'solo_sessions',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [sessionId],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// 获取所有活跃 Solo 会话列表
  Future<List<Map<String, dynamic>>> listSessions() async {
    return await _db.query(
      'solo_sessions',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
    );
  }

  /// 更新会话设置
  Future<void> updateSession({
    required String sessionId,
    String? scenePromptId,
    String? userRoleName,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().millisecondsSinceEpoch / 1000,
    };
    if (scenePromptId != null) updates['scene_prompt_id'] = scenePromptId;
    if (userRoleName != null) updates['user_role_name'] = userRoleName;

    await _db.update(
      'solo_sessions',
      updates,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 保存预构建的 system prompt 快照
  Future<void> saveSystemPrompt(String sessionId, String systemPromptJson) async {
    await _db.update(
      'solo_sessions',
      {
        'system_prompt_json': systemPromptJson,
        'updated_at': DateTime.now().millisecondsSinceEpoch / 1000,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 软删除会话
  Future<void> deleteSession(String sessionId) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await _db.update(
      'solo_sessions',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 获取完整的 chat state（复用 ChatStateService 查询逻辑）
  Future<Map<String, dynamic>> getChatState(String sessionId) async {
    return await ChatStateService.instance.ensureChatState(sessionId);
  }

  /// 确保 chat state 存在
  Future<Map<String, dynamic>> ensureChatState(String sessionId) async {
    return await ChatStateService.instance.ensureChatState(sessionId);
  }
}
