import 'dart:ui';
import '../database/database_helper.dart';

class AppConfigService {
  static final AppConfigService instance = AppConfigService._();
  AppConfigService._();

  final _db = DatabaseHelper.instance;
  final Map<String, String> _cache = {};

  Future<void> load() async {
    final all = await _db.getAllAppConfig();
    _cache.clear();
    _cache.addAll(all);
  }

  String _get(String key) => _cache[key] ?? '';

  bool getBool(String key) => _get(key) == 'true';

  bool get enableThinking => getBool('enable_thinking');
  String get defaultSystemPromptId => _get('default_system_prompt_id');
  String get agentModelChat => _get('agent_model_chat');
  String get agentModelToolAgent => _get('agent_model_tool_agent');
  String get agentModelCompression => _get('agent_model_compression');
  String get worldchatSystemPromptId => _get('worldchat_system_prompt_id');
  String get soloSystemPromptId => _get('solo_system_prompt_id');
  bool get enableSearch => getBool('enable_search');
  String get fontFamily => _get('font_family');

  Color get fontColor {
    final value = _get('font_color');
    if (value.isEmpty) return const Color(0xFF1A237E);
    return Color(int.parse(value));
  }

  int get compressionRecentKeep =>
      int.tryParse(_get('compression_recent_keep')) ?? 12;
  int get compressionABatch => int.tryParse(_get('compression_a_batch')) ?? 5;

  int get soloMemoryRounds {
    final v = int.tryParse(_get('solo_memory_rounds')) ?? 5;
    return v.clamp(2, 20);
  }
  int get soloMemoryRecentKeep =>
      int.tryParse(_get('solo_memory_recent_keep')) ?? 3;
  int get soloMemoryMaxContext =>
      int.tryParse(_get('solo_memory_max_context')) ?? 10;
  String get soloMemoryModel => _get('solo_memory_model');
  int get soloMaxHistoryRounds {
    final v = int.tryParse(_get('solo_max_history_rounds')) ?? 30;
    return v.clamp(0, 200);
  }

  Future<void> set(String key, String value) async {
    _cache[key] = value;
    await _db.setAppConfig(key, value);
  }
}
