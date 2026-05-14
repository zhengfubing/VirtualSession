import '../database/database_helper.dart';
import '../services/file_storage_service.dart';

class HomeData {
  final int totalPromptTokens;
  final int totalCompletionTokens;
  final int soloCount;
  final int castCount;
  final int sagaCount;
  final int roleCount;
  final int sceneCount;
  final int worldCount;

  int get totalTokens => totalPromptTokens + totalCompletionTokens;

  HomeData({
    required this.totalPromptTokens,
    required this.totalCompletionTokens,
    required this.soloCount,
    required this.castCount,
    required this.sagaCount,
    required this.roleCount,
    required this.sceneCount,
    required this.worldCount,
  });

  static HomeData? _cached;

  static Future<HomeData> load() async {
    if (_cached != null) return _cached!;

    final db = DatabaseHelper.instance;
    final fileStorage = FileStorageService();

    final tokenRows = await db.query('token_usage_totals');
    int promptTokens = 0;
    int completionTokens = 0;
    for (final row in tokenRows) {
      promptTokens += (row['prompt_tokens'] as int? ?? 0);
      completionTokens += (row['completion_tokens'] as int? ?? 0);
    }

    final soloRows = await db.query(
      'solo_sessions',
      where: 'deleted_at IS NULL',
    );
    final soloChats = await db.query(
      'chats',
      where: 'deleted_at IS NULL AND mode_id = ?',
      whereArgs: ['solo'],
    );
    final castRows = await db.query(
      'chats',
      where: 'deleted_at IS NULL AND (mode_id IS NULL OR mode_id != ?)',
      whereArgs: ['solo'],
    );
    final sagaRows = await db.query(
      'world_chats',
      where: 'deleted_at IS NULL',
    );

    final roles = await fileStorage.getAllRoles();
    final scenes = await fileStorage.getAllScenes();
    final worlds = await fileStorage.getAllWorlds();

    _cached = HomeData(
      totalPromptTokens: promptTokens,
      totalCompletionTokens: completionTokens,
      soloCount: soloRows.length + soloChats.length,
      castCount: castRows.length,
      sagaCount: sagaRows.length,
      roleCount: roles.length,
      sceneCount: scenes.length,
      worldCount: worlds.length,
    );

    return _cached!;
  }

  static void clear() {
    _cached = null;
  }
}
