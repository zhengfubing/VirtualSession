import 'database_helper.dart';
import '../models/prompt.dart';

class PromptDao {
  static final PromptDao instance = PromptDao._internal();
  final DatabaseHelper _db = DatabaseHelper.instance;
  
  PromptDao._internal();

  // 创建角色
  Future<int> createRole(String fileName) async {
    return await _db.insert('prompts', {
      'file_name': fileName,
      'prompt_type': 'roleSettingPrompt',
    });
  }

  // 创建场景
  Future<int> createScene(String fileName) async {
    return await _db.insert('prompts', {
      'file_name': fileName,
      'prompt_type': 'scenePrompt',
    });
  }

  // 获取所有角色
  Future<List<Prompt>> getAllRoles() async {
    final maps = await _db.query(
      'prompts',
      where: 'prompt_type = ?',
      whereArgs: ['roleSettingPrompt'],
    );
    return maps.map((m) => Prompt.fromMap(m)).toList();
  }

  // 获取所有场景
  Future<List<Prompt>> getAllScenes() async {
    final maps = await _db.query(
      'prompts',
      where: 'prompt_type = ?',
      whereArgs: ['scenePrompt'],
    );
    return maps.map((m) => Prompt.fromMap(m)).toList();
  }

  // 根据文件名获取角色
  Future<Prompt?> getRoleByFileName(String fileName) async {
    final maps = await _db.query(
      'prompts',
      where: 'file_name = ? AND prompt_type = ?',
      whereArgs: [fileName, 'roleSettingPrompt'],
    );
    return maps.isNotEmpty ? Prompt.fromMap(maps.first) : null;
  }

  // 根据文件名获取场景
  Future<Prompt?> getSceneByFileName(String fileName) async {
    final maps = await _db.query(
      'prompts',
      where: 'file_name = ? AND prompt_type = ?',
      whereArgs: [fileName, 'scenePrompt'],
    );
    return maps.isNotEmpty ? Prompt.fromMap(maps.first) : null;
  }

  // 更新角色文件名
  Future<int> updateRole(int id, String newFileName) async {
    return await _db.update(
      'prompts',
      {'file_name': newFileName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 更新场景文件名
  Future<int> updateScene(int id, String newFileName) async {
    return await _db.update(
      'prompts',
      {'file_name': newFileName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 删除角色
  Future<int> deleteRole(int id) async {
    return await _db.delete(
      'prompts',
      where: 'id = ? AND prompt_type = ?',
      whereArgs: [id, 'roleSettingPrompt'],
    );
  }

  // 删除场景
  Future<int> deleteScene(int id) async {
    return await _db.delete(
      'prompts',
      where: 'id = ? AND prompt_type = ?',
      whereArgs: [id, 'scenePrompt'],
    );
  }

  // 检查角色是否存在
  Future<bool> roleExists(String fileName) async {
    final result = await getRoleByFileName(fileName);
    return result != null;
  }

  // 检查场景是否存在
  Future<bool> sceneExists(String fileName) async {
    final result = await getSceneByFileName(fileName);
    return result != null;
  }

  // ==================== 世界相关方法 ====================

  // 创建世界
  Future<int> createWorld(String fileName) async {
    return await _db.insert('prompts', {
      'file_name': fileName,
      'prompt_type': 'world',
    });
  }

  // 获取所有世界
  Future<List<Prompt>> getAllWorlds() async {
    final maps = await _db.query(
      'prompts',
      where: 'prompt_type = ?',
      whereArgs: ['world'],
    );
    return maps.map((m) => Prompt.fromMap(m)).toList();
  }

  // 根据文件名获取世界
  Future<Prompt?> getWorldByFileName(String fileName) async {
    final maps = await _db.query(
      'prompts',
      where: 'file_name = ? AND prompt_type = ?',
      whereArgs: [fileName, 'world'],
    );
    return maps.isNotEmpty ? Prompt.fromMap(maps.first) : null;
  }

  // 更新世界文件名
  Future<int> updateWorld(int id, String newFileName) async {
    return await _db.update(
      'prompts',
      {'file_name': newFileName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 删除世界
  Future<int> deleteWorld(int id) async {
    return await _db.delete(
      'prompts',
      where: 'id = ? AND prompt_type = ?',
      whereArgs: [id, 'world'],
    );
  }

  // 检查世界是否存在
  Future<bool> worldExists(String fileName) async {
    final result = await getWorldByFileName(fileName);
    return result != null;
  }

  // ==================== 系统提示词相关方法 ====================

  // 创建系统提示词
  Future<int> createSystemPrompt(String fileName) async {
    return await _db.insert('prompts', {
      'file_name': fileName,
      'prompt_type': 'systemPrompt',
    });
  }

  // 获取所有系统提示词
  Future<List<Prompt>> getAllSystemPrompts() async {
    final maps = await _db.query(
      'prompts',
      where: 'prompt_type = ?',
      whereArgs: ['systemPrompt'],
    );
    return maps.map((m) => Prompt.fromMap(m)).toList();
  }

  // 根据文件名获取系统提示词
  Future<Prompt?> getSystemPromptByFileName(String fileName) async {
    final maps = await _db.query(
      'prompts',
      where: 'file_name = ? AND prompt_type = ?',
      whereArgs: [fileName, 'systemPrompt'],
    );
    return maps.isNotEmpty ? Prompt.fromMap(maps.first) : null;
  }

  // 更新系统提示词文件名
  Future<int> updateSystemPrompt(int id, String newFileName) async {
    return await _db.update(
      'prompts',
      {'file_name': newFileName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 删除系统提示词
  Future<int> deleteSystemPrompt(int id) async {
    return await _db.delete(
      'prompts',
      where: 'id = ? AND prompt_type = ?',
      whereArgs: [id, 'systemPrompt'],
    );
  }

  // 检查系统提示词是否存在
  Future<bool> systemPromptExists(String fileName) async {
    final result = await getSystemPromptByFileName(fileName);
    return result != null;
  }
}
