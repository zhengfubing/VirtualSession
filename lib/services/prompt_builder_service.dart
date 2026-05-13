import 'dart:convert';
import 'file_storage_service.dart';
import 'app_config_service.dart';
import '../database/database_helper.dart';

class PromptBuilderService {
  static final FileStorageService _fileStorage = FileStorageService();
  static final PromptBuilderService instance = PromptBuilderService._();
  PromptBuilderService._();

  // ── 模板渲染 ──

  static String _renderTemplate(String template, Map<String, String> values) {
    String rendered = template;
    for (final entry in values.entries) {
      rendered = rendered.replaceAll('{{${entry.key}}}', entry.value);
    }
    return rendered.trim();
  }

  /// 获取默认系统提示词 ID（从应用配置读取）
  static Future<String> _getDefaultSystemPromptId() async {
    return AppConfigService.instance.defaultSystemPromptId;
  }

  // ── Chat 系统提示词 ──

  /// 组合并渲染一次对话所需的系统提示词上下文
  static Future<Map<String, dynamic>> buildChatSystemPrompt({
    required List<String> roleSettingPromptIds,
    required String scenePromptId,
    required String senderName,
    required String userInput,
  }) async {
    // 1. 加载系统提示词模板
    final systemPromptId = await _getDefaultSystemPromptId();
    String systemPromptTemplate = '';
    if (systemPromptId.isNotEmpty && systemPromptId != 'empty') {
      systemPromptTemplate =
          (await _fileStorage.readSystemPrompt(systemPromptId)) ?? '';
    }

    // 2. 加载场景背景
    String sceneBackground = '';
    if (scenePromptId.isNotEmpty && scenePromptId != 'empty') {
      sceneBackground = (await _fileStorage.readScene(scenePromptId)) ?? '';
    }

    // 3. 构建参与者列表和角色详细设定
    final participants = <String>[];
    final roleDetails = <String>[];
    final uniqueIds = roleSettingPromptIds
        .where((id) => id.isNotEmpty && id != 'empty')
        .toSet()
        .toList()
      ..sort();

    for (final rid in uniqueIds) {
      final rname = rid.replaceAll('.md', '');
      participants.add(rname);
      final setting = (await _fileStorage.readRole(rid))?.trim() ?? '';
      if (setting.isNotEmpty) {
        roleDetails.add('人物 $rname 设定：\n$setting');
      }
    }

    // 4. 计算模板变量
    final sceneName = scenePromptId != 'empty'
        ? scenePromptId.replaceAll('.md', '')
        : '未定义场景';
    final currentSenderName =
        senderName.isNotEmpty && senderName != 'empty'
            ? senderName.replaceAll('.md', '')
            : 'user';
    final candidateParticipants =
        participants.where((name) => name != currentSenderName).toList();
    final candidateText = candidateParticipants.isNotEmpty
        ? candidateParticipants.join('，')
        : '无可选人物';

    // 从用户输入中提取 @提及
    final mentionMatch =
        RegExp(r"@([^\s，。,:：!?！？]+)").firstMatch(userInput);
    final mentionedName = mentionMatch?.group(1)?.trim() ?? '';
    final mentionInParticipants = participants.contains(mentionedName);
    final mentionIsValid = mentionedName.isNotEmpty &&
        mentionInParticipants &&
        mentionedName != currentSenderName;
    final mentionTargetText = mentionIsValid ? mentionedName : '无';

    // 5. 渲染模板
    final templateValues = {
      'scene_name': sceneName,
      'participants':
          participants.isNotEmpty ? participants.join('，') : '未选择',
      'current_sender_name': currentSenderName,
      'candidate_text': candidateText,
      'mention_target_text': mentionTargetText,
      'scene_background': sceneBackground.trim(),
      'role_details':
          roleDetails.isNotEmpty ? roleDetails.join('\n') : '无',
    };
    final fullSystemPrompt =
        _renderTemplate(systemPromptTemplate, templateValues);

    return {
      'full_system_prompt': fullSystemPrompt,
      'scene_name': sceneName,
      'participants': participants,
      'current_sender_name': currentSenderName,
    };
  }

  // ── Solo 系统提示词 ──

  /// 组合并渲染 Solo 模式（单场景双角色：用户角色 + AI角色）的系统提示词
  static Future<Map<String, dynamic>> buildSoloSystemPrompt({
    required String userRoleName,
    required String aiRoleName,
    required String scenePromptId,
  }) async {
    // 1. 加载 Solo 系统提示词模板
    final soloSystemPromptId = AppConfigService.instance.soloSystemPromptId;
    String systemPromptTemplate = '';
    if (soloSystemPromptId.isNotEmpty && soloSystemPromptId != 'empty') {
      systemPromptTemplate =
          (await _fileStorage.readSystemPrompt(soloSystemPromptId)) ?? '';
    }

    // 2. 加载场景背景
    String sceneBackground = '';
    if (scenePromptId.isNotEmpty && scenePromptId != 'empty') {
      sceneBackground = (await _fileStorage.readScene(scenePromptId)) ?? '';
    }

    // 3. 加载用户角色设定
    final userRoleSetting =
        (await _fileStorage.readRole(userRoleName))?.trim() ?? '';
    final userRoleDetails = userRoleSetting.isNotEmpty
        ? '$userRoleName 设定：\n$userRoleSetting'
        : '无';

    // 4. 加载AI角色设定
    final aiRoleSetting =
        (await _fileStorage.readRole(aiRoleName))?.trim() ?? '';
    final aiRoleDetails =
        aiRoleSetting.isNotEmpty ? '$aiRoleName 设定：\n$aiRoleSetting' : '无';

    // 5. 计算模板变量
    final sceneName = scenePromptId != 'empty'
        ? scenePromptId.replaceAll('.md', '')
        : '未定义场景';

    // 6. 渲染模板
    final templateValues = {
      'scene_name': sceneName,
      'scene_background': sceneBackground.trim(),
      'user_role_name': userRoleName,
      'user_role_details': userRoleDetails,
      'ai_role_name': aiRoleName,
      'ai_role_details': aiRoleDetails,
    };
    var fullSystemPrompt =
        _renderTemplate(systemPromptTemplate, templateValues);

    // 7. 注入远古记忆（被淘汰的记忆写入系统提示词）
    final ancientSection = await _buildAncientMemoriesSection(
      sessionId: aiRoleName.replaceAll('.md', ''),
    );
    if (ancientSection != null) {
      fullSystemPrompt = '$fullSystemPrompt\n$ancientSection';
    }

    return {
      'full_system_prompt': fullSystemPrompt,
      'scene_name': sceneName,
      'user_role_name': userRoleName,
      'ai_role_name': aiRoleName,
    };
  }

  /// 构建远古记忆区段
  /// 查询已从 context_items 淘汰的记忆，写入系统提示词作为持久背景
  static Future<String?> _buildAncientMemoriesSection({
    required String sessionId,
  }) async {
    final cfg = AppConfigService.instance;
    final H = cfg.soloMaxHistoryRounds;
    if (H == 0) return null;

    final db = DatabaseHelper.instance;

    // 1. 获取当前活跃的 memory_ref IDs（这些在上下文中，不重复）
    final activeRefs = await db.query(
      'context_items',
      where: 'chat_id = ? AND item_type = ? AND active = 1',
      whereArgs: [sessionId, 'memory_ref'],
    );
    final activeMemoryIds = <String>{};
    for (final ref in activeRefs) {
      try {
        final content = jsonDecode(ref['content'] as String? ?? '{}');
        final mid = content['memory_id'] as String?;
        if (mid != null && mid.isNotEmpty) activeMemoryIds.add(mid);
      } catch (_) {}
    }

    // 2. 查询该 session 所有记忆，排除活跃的
    final allMemories = await db.query(
      'solo_memories',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
    );
    if (allMemories.isEmpty) return null;

    // 3. 计算最多纳入条数
    final M = cfg.soloMemoryRounds;
    final B = cfg.compressionABatch;
    final roundsPerMemory = M * B / 2.0;
    final maxCount = (H / roundsPerMemory).ceil().clamp(1, 50);

    // 4. 取已淘汰的记忆（不在活跃 context 中）
    final trimmed = allMemories
        .where((m) => !activeMemoryIds.contains(m['id'] as String))
        .take(maxCount)
        .toList();
    if (trimmed.isEmpty) return null;

    // 5. 构建远古记忆文本
    final buf = StringBuffer();
    buf.writeln('## 远古记忆');
    buf.writeln('以下是更早以前的对话记忆摘要，仅作为遥远的背景参考：');
    buf.writeln();
    for (final m in trimmed) {
      final brief = (m['brief'] as String? ?? '').trim();
      if (brief.isNotEmpty) {
        buf.writeln('- $brief');
      }
    }

    return buf.toString();
  }

  // ── WorldChat 系统提示词 ──

  /// 构建角色详细设定文本
  static Future<String> _buildRoleSettings(List<String> roleNames) async {
    final lines = <String>[];
    for (final name in roleNames) {
      final setting = await _fileStorage.readRole(name);
      if (setting != null && setting.trim().isNotEmpty) {
        lines.add('### $name');
        lines.add(setting.trim());
        lines.add('');
      } else {
        lines.add('### $name');
        lines.add('$name 是一个角色。');
        lines.add('');
      }
    }
    return lines.isNotEmpty ? lines.join('\n') : '暂无角色设定';
  }

  /// 构建世界聊天系统提示词
  static Future<String> buildWorldSystemPrompt({
    required String worldSceneId,
    required String currentScene,
    required List<String> roleNames,
    required List<String> sceneRoles,
    required Map<String, String> roleLocations,
  }) async {
    // 1. 加载世界场景内容
    String worldContent =
        (await _fileStorage.readWorld(worldSceneId)) ??
            '# $worldSceneId\n\n$worldSceneId 的世界。';

    // 2. 加载当前场景内容
    String sceneContent =
        (await _fileStorage.readScene(currentScene)) ??
            '$currentScene 的场景。';

    // 3. 加载世界聊天系统提示词模板
    final worldSystemPromptId = AppConfigService.instance.worldchatSystemPromptId;
    String template =
        (await _fileStorage.readSystemPrompt(worldSystemPromptId)) ?? '';

    // 4. 构建各部分文本
    final roleSettingsText = await _buildRoleSettings(roleNames);
    final sceneRolesText = sceneRoles.isNotEmpty
        ? sceneRoles.map((r) => '- $r').join('\n')
        : '（当前场景无角色）';
    final locationsSummary = roleLocations.isNotEmpty
        ? roleLocations.entries
            .map((e) => '- ${e.key.replaceAll('.md', '')}：${e.value}')
            .join('\n')
        : '暂无位置信息';
    final allRolesText =
        roleNames.isNotEmpty ? roleNames.join('、') : '无';

    // 5. 渲染模板
    final values = {
      'world_scene_content': worldContent,
      'world_scene': worldSceneId,
      'current_scene': currentScene,
      'scene_description': sceneContent,
      'scene_roles': sceneRolesText,
      'all_roles': allRolesText,
      'role_locations_summary': locationsSummary,
    };
    final rendered = _renderTemplate(template, values);

    // 6. 拼接角色详细设定
    final fullPrompt = '$rendered\n\n## 角色详细设定\n\n$roleSettingsText';
    return fullPrompt.trim();
  }
}
