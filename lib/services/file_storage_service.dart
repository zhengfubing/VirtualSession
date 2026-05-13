import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class FileStorageService {
  static final FileStorageService _instance = FileStorageService._internal();
  factory FileStorageService() => _instance;
  FileStorageService._internal();

  // 获取应用文档目录
  Future<Directory> get _appDir async {
    final dir = await getApplicationDocumentsDirectory();
    return dir;
  }

  // 获取角色目录
  Future<Directory> get _rolesDir async {
    final dir = await _appDir;
    final rolesDir = Directory(path.join(dir.path, 'roles'));
    if (!await rolesDir.exists()) {
      await rolesDir.create(recursive: true);
    }
    return rolesDir;
  }

  // 获取场景目录
  Future<Directory> get _scenesDir async {
    final dir = await _appDir;
    final scenesDir = Directory(path.join(dir.path, 'scenes'));
    if (!await scenesDir.exists()) {
      await scenesDir.create(recursive: true);
    }
    return scenesDir;
  }

  // 保存角色文件
  Future<void> saveRole(String name, String content) async {
    final dir = await _rolesDir;
    final file = File(path.join(dir.path, '$name.md'));
    await file.writeAsString(content);
  }

  // 读取角色文件
  Future<String?> readRole(String name) async {
    try {
      final dir = await _rolesDir;
      final file = File(path.join(dir.path, '$name.md'));
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 删除角色文件
  Future<void> deleteRole(String name) async {
    final dir = await _rolesDir;
    final file = File(path.join(dir.path, '$name.md'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  // 重命名角色文件
  Future<void> renameRole(String oldName, String newName, String content) async {
    await deleteRole(oldName);
    await saveRole(newName, content);
  }

  // 获取所有角色名称列表
  Future<List<String>> getAllRoles() async {
    final dir = await _rolesDir;
    if (!await dir.exists()) return [];
    
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.md'))
        .map((file) => path.basenameWithoutExtension(file.path))
        .toList();

    return files;
  }

  // 保存场景文件
  Future<void> saveScene(String name, String content) async {
    final dir = await _scenesDir;
    final file = File(path.join(dir.path, '$name.md'));
    await file.writeAsString(content);
  }

  // 读取场景文件
  Future<String?> readScene(String name) async {
    try {
      final dir = await _scenesDir;
      final file = File(path.join(dir.path, '$name.md'));
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 删除场景文件
  Future<void> deleteScene(String name) async {
    final dir = await _scenesDir;
    final file = File(path.join(dir.path, '$name.md'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  // 重命名场景文件
  Future<void> renameScene(String oldName, String newName, String content) async {
    await deleteScene(oldName);
    await saveScene(newName, content);
  }

  // 获取所有场景名称列表
  Future<List<String>> getAllScenes() async {
    final dir = await _scenesDir;
    if (!await dir.exists()) return [];
    
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.md'))
        .map((file) => path.basenameWithoutExtension(file.path))
        .toList();

    return files;
  }

  // 获取世界目录
  Future<Directory> get _worldsDir async {
    final dir = await _appDir;
    final worldsDir = Directory(path.join(dir.path, 'worlds'));
    if (!await worldsDir.exists()) {
      await worldsDir.create(recursive: true);
    }
    return worldsDir;
  }

  // 保存世界文件
  Future<void> saveWorld(String name, String content) async {
    final dir = await _worldsDir;
    final file = File(path.join(dir.path, '$name.md'));
    await file.writeAsString(content);
  }

  // 读取世界文件
  Future<String?> readWorld(String name) async {
    try {
      final dir = await _worldsDir;
      final file = File(path.join(dir.path, '$name.md'));
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 删除世界文件
  Future<void> deleteWorld(String name) async {
    final dir = await _worldsDir;
    final file = File(path.join(dir.path, '$name.md'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  // 重命名世界文件
  Future<void> renameWorld(String oldName, String newName, String content) async {
    await deleteWorld(oldName);
    await saveWorld(newName, content);
  }

  // 获取所有世界名称列表
  Future<List<String>> getAllWorlds() async {
    final dir = await _worldsDir;
    if (!await dir.exists()) return [];
    
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.md'))
        .map((file) => path.basenameWithoutExtension(file.path))
        .toList();

    return files;
  }

  // ==================== 头像相关方法 ====================

  // 获取头像目录
  Future<Directory> get _avatarsDir async {
    final dir = await _appDir;
    final avatarsDir = Directory(path.join(dir.path, 'avatars'));
    if (!await avatarsDir.exists()) {
      await avatarsDir.create(recursive: true);
    }
    return avatarsDir;
  }

  // 保存角色头像（使用角色名称作为文件名）
  Future<String> saveRoleAvatar(String roleName, List<int> imageBytes) async {
    final dir = await _avatarsDir;
    final file = File(path.join(dir.path, '$roleName.png'));
    await file.writeAsBytes(imageBytes);
    return file.path;
  }

  // 获取角色头像路径
  Future<String?> getRoleAvatarPath(String roleName) async {
    final dir = await _avatarsDir;
    final file = File(path.join(dir.path, '$roleName.png'));
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  // 删除角色头像
  Future<void> deleteRoleAvatar(String roleName) async {
    final dir = await _avatarsDir;
    final file = File(path.join(dir.path, '$roleName.png'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  // 重命名角色头像（当角色重命名时调用）
  Future<void> renameRoleAvatar(String oldRoleName, String newRoleName) async {
    final dir = await _avatarsDir;
    final oldFile = File(path.join(dir.path, '$oldRoleName.png'));
    final newFile = File(path.join(dir.path, '$newRoleName.png'));
    
    if (await oldFile.exists()) {
      await oldFile.rename(newFile.path);
    }
  }

  // 检查角色是否有头像
  Future<bool> hasRoleAvatar(String roleName) async {
    final dir = await _avatarsDir;
    final file = File(path.join(dir.path, '$roleName.png'));
    return await file.exists();
  }

  // ==================== 系统提示词相关方法 ====================

  // 获取系统提示词目录
  Future<Directory> get _systemPromptsDir async {
    final dir = await _appDir;
    final systemPromptsDir = Directory(path.join(dir.path, 'system_prompts'));
    if (!await systemPromptsDir.exists()) {
      await systemPromptsDir.create(recursive: true);
    }
    return systemPromptsDir;
  }

  // 保存系统提示词文件
  Future<void> saveSystemPrompt(String name, String content) async {
    final dir = await _systemPromptsDir;
    final file = File(path.join(dir.path, '$name.md'));
    await file.writeAsString(content);
  }

  // 读取系统提示词文件
  Future<String?> readSystemPrompt(String name) async {
    try {
      final dir = await _systemPromptsDir;
      final file = File(path.join(dir.path, '$name.md'));
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 删除系统提示词文件
  Future<void> deleteSystemPrompt(String name) async {
    final dir = await _systemPromptsDir;
    final file = File(path.join(dir.path, '$name.md'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  // 重命名系统提示词文件
  Future<void> renameSystemPrompt(String oldName, String newName, String content) async {
    await deleteSystemPrompt(oldName);
    await saveSystemPrompt(newName, content);
  }

  // 获取所有系统提示词名称列表
  Future<List<String>> getAllSystemPrompts() async {
    final dir = await _systemPromptsDir;
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.md'))
        .map((file) => path.basenameWithoutExtension(file.path))
        .toList();

    return files;
  }

  // ==================== 记忆相关方法 ====================

  Future<Directory> get _memoriesDir async {
    final dir = await _appDir;
    final d = Directory(path.join(dir.path, 'memories'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> saveMemory(String id, String content) async {
    final dir = await _memoriesDir;
    await File(path.join(dir.path, '$id.md')).writeAsString(content);
  }

  Future<String?> readMemory(String id) async {
    final dir = await _memoriesDir;
    final file = File(path.join(dir.path, '$id.md'));
    return await file.exists() ? await file.readAsString() : null;
  }

  /// 通用 prompt 读取方法，根据 promptType 分发到对应目录
  Future<String> readPrompt(String fileName, String promptType) async {
    final name = fileName.replaceAll('.md', '');
    String? content;
    switch (promptType) {
      case 'roleSettingPrompt':
        content = await readRole(name);
        break;
      case 'scenePrompt':
        content = await readScene(name);
        break;
      case 'world':
        content = await readWorld(name);
        break;
      case 'systemPrompt':
        content = await readSystemPrompt(name);
        break;
    }
    return content ?? '';
  }
}
