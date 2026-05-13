import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/ai_model.dart';
import '../services/app_config_service.dart';
import '../services/file_storage_service.dart';
import '../theme/app_colors.dart';

class _ModelEntry {
  int? id;
  final TextEditingController nameCtrl;
  final TextEditingController urlCtrl;
  final TextEditingController keyCtrl;

  _ModelEntry({
    this.id,
    required String name,
    required String baseUrl,
    required String apiKey,
  }) : nameCtrl = TextEditingController(text: name),
       urlCtrl = TextEditingController(text: baseUrl),
       keyCtrl = TextEditingController(text: apiKey);

  void dispose() {
    nameCtrl.dispose();
    urlCtrl.dispose();
    keyCtrl.dispose();
  }
}

class AppConfigPage extends StatefulWidget {
  const AppConfigPage({super.key});

  @override
  State<AppConfigPage> createState() => _AppConfigPageState();
}

class _AppConfigPageState extends State<AppConfigPage> {
  final _config = AppConfigService.instance;
  final _db = DatabaseHelper.instance;
  final _fileStorage = FileStorageService();

  // Master key
  final _masterKeyCtrl = TextEditingController();

  // Model entries
  List<String> _modelNames = [];
  final List<_ModelEntry> _modelEntries = [];

  // Chat settings
  bool _enableThinking = false;
  bool _enableSearch = false;
  String _defaultSystemPromptId = '';
  String _worldchatSystemPromptId = '';
  String _soloSystemPromptId = '';
  List<String> _systemPromptNames = [];

  // Agent model config
  String _modelChat = '';
  String _modelCompression = '';

  // Compression config
  final _recentKeepCtrl = TextEditingController();
  final _aBatchCtrl = TextEditingController();

  // Solo memory config
  String _modelMemory = '';
  final _memoryRoundsCtrl = TextEditingController();
  final _memoryRecentKeepCtrl = TextEditingController();
  final _memoryMaxContextCtrl = TextEditingController();
  final _maxHistoryRoundsCtrl = TextEditingController();

  // TTS config
  final _ttsApiKeyCtrl = TextEditingController();
  final _ttsBaseUrlCtrl = TextEditingController();
  final _ttsModelCtrl = TextEditingController();
  final _ttsVoiceCtrl = TextEditingController();
  final _ttsLanguageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _enableThinking = _config.enableThinking;
    _enableSearch = _config.enableSearch;
    _defaultSystemPromptId = _config.defaultSystemPromptId;
    _worldchatSystemPromptId = _config.worldchatSystemPromptId;
    _soloSystemPromptId = _config.soloSystemPromptId;
    _modelChat = _config.agentModelChat;
    _modelCompression = _config.agentModelCompression;
    _recentKeepCtrl.text = _config.compressionRecentKeep.toString();
    _aBatchCtrl.text = _config.compressionABatch.toString();
    _modelMemory = _config.soloMemoryModel;
    _memoryRoundsCtrl.text = _config.soloMemoryRounds.toString();
    _memoryRecentKeepCtrl.text = _config.soloMemoryRecentKeep.toString();
    _memoryMaxContextCtrl.text = _config.soloMemoryMaxContext.toString();
    _maxHistoryRoundsCtrl.text = _config.soloMaxHistoryRounds.toString();

    _loadModelEntries();
    _loadSystemPromptNames();
    _loadTtsConfig();

    _masterKeyCtrl.addListener(_onMasterKeyChanged);

    // 监听容量相关参数变化，实时更新计算结果
    void onParamChanged() => setState(() {});
    _recentKeepCtrl.addListener(onParamChanged);
    _aBatchCtrl.addListener(onParamChanged);
    _memoryRoundsCtrl.addListener(onParamChanged);
    _memoryRecentKeepCtrl.addListener(onParamChanged);
    _memoryMaxContextCtrl.addListener(onParamChanged);
    _maxHistoryRoundsCtrl.addListener(onParamChanged);
  }

  void _onMasterKeyChanged() {
    final key = _masterKeyCtrl.text;
    _ttsApiKeyCtrl.text = key;
    for (final entry in _modelEntries) {
      entry.keyCtrl.text = key;
    }
  }

  Future<void> _loadModelEntries() async {
    final models = await _db.getAllModels();
    for (final e in _modelEntries) {
      e.dispose();
    }
    if (mounted) {
      setState(() {
        _modelEntries.clear();
        for (final m in models) {
          final model = AIModel.fromMap(m);
          _modelEntries.add(
            _ModelEntry(
              id: model.id,
              name: model.name,
              baseUrl: model.baseUrl,
              apiKey: model.apiKey,
            ),
          );
        }
        _modelNames = _modelEntries.map((e) => e.nameCtrl.text).toList();
      });
    }
  }

  Future<void> _loadSystemPromptNames() async {
    final names = await _fileStorage.getAllSystemPrompts();
    if (mounted) {
      setState(() {
        _systemPromptNames = names;
      });
    }
  }

  Future<void> _loadTtsConfig() async {
    final tts = await _db.getAllTtsConfig();
    if (!mounted) return;
    setState(() {
      _ttsApiKeyCtrl.text = tts['tts_api_key'] ?? '';
      _ttsBaseUrlCtrl.text =
          tts['tts_base_url'] ?? 'https://dashscope.aliyuncs.com/api/v1';
      _ttsModelCtrl.text = tts['tts_model'] ?? 'qwen3-tts-flash';
      _ttsVoiceCtrl.text = tts['tts_voice'] ?? 'Cherry';
      _ttsLanguageCtrl.text = tts['tts_language'] ?? 'Chinese';
    });
  }

  void _addNewModel() {
    setState(() {
      _modelEntries.add(_ModelEntry(name: '', baseUrl: '', apiKey: ''));
    });
  }

  Future<void> _removeModel(int index) async {
    final entry = _modelEntries[index];
    if (entry.id != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认删除'),
          content: Text('确定要删除模型 "${entry.nameCtrl.text}" 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('删除', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _db.deleteModel(entry.id!);
    }
    setState(() {
      entry.dispose();
      _modelEntries.removeAt(index);
      _modelNames = _modelEntries.map((e) => e.nameCtrl.text).toList();
    });
  }

  @override
  void dispose() {
    _masterKeyCtrl.removeListener(_onMasterKeyChanged);
    for (final e in _modelEntries) {
      e.dispose();
    }
    _masterKeyCtrl.dispose();
    _ttsApiKeyCtrl.dispose();
    _ttsBaseUrlCtrl.dispose();
    _ttsModelCtrl.dispose();
    _ttsVoiceCtrl.dispose();
    _ttsLanguageCtrl.dispose();
    _recentKeepCtrl.dispose();
    _aBatchCtrl.dispose();
    _memoryRoundsCtrl.dispose();
    _memoryRecentKeepCtrl.dispose();
    _memoryMaxContextCtrl.dispose();
    _maxHistoryRoundsCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    // TTS API key
    await _db.setTtsConfig('tts_api_key', _ttsApiKeyCtrl.text.trim());

    // Model entries
    for (final entry in _modelEntries) {
      final name = entry.nameCtrl.text.trim();
      final url = entry.urlCtrl.text.trim();
      final key = entry.keyCtrl.text.trim();
      if (name.isEmpty || url.isEmpty) continue;
      final data = {'name': name, 'base_url': url, 'api_key': key};
      if (entry.id != null) {
        await _db.updateModel(entry.id!, data);
      } else {
        final id = await _db.createModel(data);
        entry.id = id;
      }
    }
    setState(() {
      _modelNames = _modelEntries
          .map((e) => e.nameCtrl.text.trim())
          .where((n) => n.isNotEmpty)
          .toList();
    });

    // App config
    await _config.set('enable_thinking', _enableThinking.toString());
    await _config.set('enable_search', _enableSearch.toString());
    await _config.set('default_system_prompt_id', _defaultSystemPromptId);
    await _config.set('agent_model_chat', _modelChat);
    await _config.set('agent_model_compression', _modelCompression);
    await _config.set('worldchat_system_prompt_id', _worldchatSystemPromptId);
    await _config.set('solo_system_prompt_id', _soloSystemPromptId);
    await _config.set('compression_recent_keep', _recentKeepCtrl.text.trim());
    await _config.set('compression_a_batch', _aBatchCtrl.text.trim());
    await _config.set('solo_memory_model', _modelMemory);
    await _config.set('solo_memory_rounds', _memoryRoundsCtrl.text.trim());
    await _config.set(
      'solo_memory_recent_keep',
      _memoryRecentKeepCtrl.text.trim(),
    );
    await _config.set(
      'solo_memory_max_context',
      _memoryMaxContextCtrl.text.trim(),
    );
    await _config.set(
      'solo_max_history_rounds',
      _maxHistoryRoundsCtrl.text.trim(),
    );

    // TTS advanced config
    await Future.wait([
      _db.setTtsConfig('tts_base_url', _ttsBaseUrlCtrl.text.trim()),
      _db.setTtsConfig('tts_model', _ttsModelCtrl.text.trim()),
      _db.setTtsConfig('tts_voice', _ttsVoiceCtrl.text.trim()),
      _db.setTtsConfig('tts_language', _ttsLanguageCtrl.text.trim()),
    ]);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('配置已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: AppColors.appBarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text(
          '应用配置',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            color: AppColors.accent,
            onPressed: _saveAll,
            tooltip: '保存配置',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── 统一 API Key ──
          _sectionTitle('傻瓜式无脑配置', Icons.vpn_key_outlined),
          const SizedBox(height: 10),
          _card(
            children: [
              TextField(
                controller: _masterKeyCtrl,
                decoration: const InputDecoration(
                  labelText: '统一 API Key',
                  hintText: '粘贴百炼 API Key，自动同步所有密钥',
                  isDense: true,
                ),
                obscureText: true,
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── 聊天设置 ──
          _sectionTitle('聊天设置', Icons.chat_outlined),
          const SizedBox(height: 10),
          _card(
            children: [
              SwitchListTile(
                title: const Text('启用深度思考'),
                subtitle: const Text('开启后模型会展示推理过程'),
                value: _enableThinking,
                onChanged: (v) => setState(() => _enableThinking = v),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('联网搜索'),
                subtitle: const Text('开启后模型可自动联网搜索信息'),
                value: _enableSearch,
                onChanged: (v) => setState(() => _enableSearch = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 14),
              _systemPromptDropdown(
                '会话系统提示词',
                _defaultSystemPromptId,
                (v) => setState(() => _defaultSystemPromptId = v ?? ''),
              ),
              const SizedBox(height: 14),
              _systemPromptDropdown(
                '世界系统提示词',
                _worldchatSystemPromptId,
                (v) => setState(() => _worldchatSystemPromptId = v ?? ''),
              ),
              const SizedBox(height: 14),
              _systemPromptDropdown(
                '独幕系统提示词',
                _soloSystemPromptId,
                (v) => setState(() => _soloSystemPromptId = v ?? ''),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Agent 模型配置 ──
          _sectionTitle('Agent 模型配置', Icons.smart_toy_outlined),
          const SizedBox(height: 10),
          _card(
            children: [
              _modelDropdown(
                '对话模型',
                _modelChat,
                (v) => setState(() => _modelChat = v!),
              ),
              const SizedBox(height: 14),
              _modelDropdown(
                '压缩模型',
                _modelCompression,
                (v) => setState(() => _modelCompression = v!),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── 压缩配置 ──
          _sectionTitle('压缩配置', Icons.compress_outlined),
          const SizedBox(height: 10),
          _card(
            children: [
              TextField(
                controller: _recentKeepCtrl,
                decoration: const InputDecoration(
                  labelText: '保留原始消息数',
                  hintText: '12',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _aBatchCtrl,
                decoration: const InputDecoration(
                  labelText: '每次压缩源消息数',
                  hintText: '5',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Solo 记忆配置 ──
          _sectionTitle('Solo 记忆配置', Icons.memory_outlined),
          const SizedBox(height: 10),
          _card(
            children: [
              _modelDropdown(
                '记忆提取模型',
                _modelMemory,
                (v) => setState(() => _modelMemory = v ?? ''),
              ),
              const SizedBox(height: 6),
              Text(
                '用于将多轮摘要提炼为结构化记忆，推荐使用便宜模型',
                style: TextStyle(fontSize: 11, color: AppColors.subText),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _memoryRoundsCtrl,
                decoration: const InputDecoration(
                  labelText: '记忆提取轮次',
                  hintText: '5（取值范围 2-20）',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 6),
              Text(
                '每 N 次压缩触发一次记忆提取，值越小提取越频繁',
                style: TextStyle(fontSize: 11, color: AppColors.subText),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _memoryRecentKeepCtrl,
                decoration: const InputDecoration(
                  labelText: '记忆保留最近摘要数',
                  hintText: '3',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 6),
              Text(
                '最近 N 个摘要不被记忆消费，仍在上下文中使用',
                style: TextStyle(fontSize: 11, color: AppColors.subText),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _memoryMaxContextCtrl,
                decoration: const InputDecoration(
                  labelText: '上下文最大记忆引用数',
                  hintText: '10',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 6),
              Text(
                '上下文中最多保留 N 个 memory_ref，超出淘汰最老的',
                style: TextStyle(fontSize: 11, color: AppColors.subText),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _maxHistoryRoundsCtrl,
                decoration: const InputDecoration(
                  labelText: '远古记忆轮次上限',
                  hintText: '30（0=禁用，最大200）',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 6),
              Text(
                '被淘汰的记忆写入系统提示词"远古记忆"区，最多覆盖 N 轮',
                style: TextStyle(fontSize: 11, color: AppColors.subText),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Solo 会话容量计算 ──
          _sectionTitle('Solo 会话容量计算', Icons.calculate_outlined),
          const SizedBox(height: 10),
          _buildSoloCapacityCard(),
          const SizedBox(height: 28),

          // ── TTS 语音合成配置 ──
          _sectionTitle('TTS 语音合成配置', Icons.record_voice_over_outlined),
          const SizedBox(height: 10),
          _card(
            children: [
              TextField(
                controller: _ttsApiKeyCtrl,
                decoration: const InputDecoration(labelText: 'API Key'),
                obscureText: true,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ttsBaseUrlCtrl,
                decoration: const InputDecoration(labelText: 'Base URL'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ttsModelCtrl,
                decoration: const InputDecoration(labelText: '模型'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ttsVoiceCtrl,
                decoration: const InputDecoration(labelText: '默认音色'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ttsLanguageCtrl,
                decoration: const InputDecoration(labelText: '语言'),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── 模型管理 ──
          _sectionTitle('模型管理', Icons.storage_outlined),
          const SizedBox(height: 10),
          _card(children: [_buildModelSection()]),
        ],
      ),
    );
  }

  // ==================== Solo 会话容量计算 ====================

  int _parseInt(TextEditingController ctrl, int fallback) {
    return int.tryParse(ctrl.text.trim()) ?? fallback;
  }

  Map<String, dynamic> _computeSoloCapacity() {
    final R = _parseInt(_recentKeepCtrl, 12);
    final B = _parseInt(_aBatchCtrl, 5);
    final M = _parseInt(_memoryRoundsCtrl, 5).clamp(2, 20);
    final K = _parseInt(_memoryRecentKeepCtrl, 3);
    final C = _parseInt(_memoryMaxContextCtrl, 10);
    final H = _parseInt(_maxHistoryRoundsCtrl, 30).clamp(0, 200);

    // 每轮 2 条消息，每条记忆覆盖的轮次
    final roundsPerMemory = M * B / 2.0;

    // 首次压缩触发轮次
    final firstCompress = (R + B + 1) ~/ 2;

    // 首次记忆提取轮次
    final firstMemory = ((K + M) * B + R + 1) ~/ 2;

    // 记忆提取周期（轮/记忆）
    final memoryInterval = roundsPerMemory.toStringAsFixed(1);

    // 上下文稳态轮次
    final steadyRound = firstMemory + (M * B ~/ 2);

    // 远古记忆条数与实际覆盖轮次
    final ancientCount =
        H == 0 ? 0 : (H / roundsPerMemory).ceil().clamp(0, 50);
    final ancientRounds = ancientCount * roundsPerMemory;

    // 历史记忆深度（轮）= 原始消息 + 活跃摘要 + 活跃记忆 + 远古记忆
    final memoryDepth =
        (R / 2.0) + ((K + M - 1) * B / 2.0) + (C * M * B / 2.0) + ancientRounds;

    return {
      'R': R,
      'B': B,
      'M': M,
      'K': K,
      'C': C,
      'H': H,
      'roundsPerMemory': roundsPerMemory,
      'firstCompress': firstCompress,
      'firstMemory': firstMemory,
      'memoryInterval': memoryInterval,
      'steadyRound': steadyRound,
      'memoryDepth': memoryDepth.round(),
      'ancientCount': ancientCount,
      'ancientRounds': ancientRounds.toStringAsFixed(1),
      'contextBreakdown':
          'system_prompt + 远古记忆($ancientCount条) + ≤$C×memory_ref + ≤${K + M - 1}×summary + $R×raw_msg',
    };
  }

  Widget _buildSoloCapacityCard() {
    final cap = _computeSoloCapacity();

    return _card(
      children: [
        _capacityRow(
          '首次压缩触发',
          '第 ${cap['firstCompress']} 轮',
          '可压缩消息 > R(${cap['R']}) 且 候选 ≥ B(${cap['B']})',
        ),
        const SizedBox(height: 10),
        _capacityRow(
          '首次记忆提取',
          '第 ${cap['firstMemory']} 轮',
          '活跃摘要 ≥ K(${cap['K']}) + M(${cap['M']}) = ${(cap['K'] as int) + (cap['M'] as int)} 条',
        ),
        const SizedBox(height: 10),
        _capacityRow(
          '记忆提取周期',
          '每 ${cap['memoryInterval']} 轮',
          'M(${cap['M']}) × B(${cap['B']}) ÷ 2 = ${cap['memoryInterval']} 轮/记忆',
        ),
        const SizedBox(height: 10),
        _capacityRow(
          '上下文稳态',
          '约第 ${cap['steadyRound']} 轮',
          '首次记忆提取后，压缩+记忆管线进入稳态',
        ),
        const Divider(height: 24),
        _capacityRow(
          '历史记忆深度',
          '约 ${cap['memoryDepth']} 轮',
          'R/2 + (K+M-1)×B/2 + C×M×B/2 + 远古覆盖(${cap['ancientRounds']})',
        ),
        const SizedBox(height: 10),
        _capacityRow(
          '远古记忆',
          cap['H'] == 0
              ? '已禁用'
              : '${cap['ancientCount']} 条（上限 ${cap['H']} 轮，实际覆盖 ${cap['ancientRounds']} 轮）',
          cap['H'] == 0
              ? 'H=0，被淘汰的记忆直接丢弃'
              : 'ceil(H ÷ ${cap['roundsPerMemory']}) = ${cap['ancientCount']} 条，写入系统提示词每轮携带',
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.divider.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '稳态上下文大小有界：${cap['contextBreakdown']}\n'
                  '模型上下文窗口 > 稳态上下文 → 理论上无限轮次。\n'
                  '总记忆深度 ≈ ${cap['memoryDepth']} 轮，'
                  '${cap['H'] == 0 ? "超出后直接丢弃。" : "超出后最老远古记忆被挤出。"}',
                  style: TextStyle(fontSize: 12, color: AppColors.subText, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _capacityRow(String label, String value, String detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: AppColors.text),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          style: TextStyle(fontSize: 11, color: AppColors.subText),
        ),
      ],
    );
  }

  // ================================================================

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _modelDropdown(
    String label,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value.isEmpty ? null : value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: _modelNames
          .map((name) => DropdownMenuItem(value: name, child: Text(name)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _systemPromptDropdown(
    String label,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value.isEmpty ? null : value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: _systemPromptNames
          .map(
            (name) => DropdownMenuItem(
              value: name,
              child: Text(name.replaceAll('.md', '')),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildModelSection() {
    return Column(
      children: [
        ..._modelEntries.asMap().entries.map((mapEntry) {
          final i = mapEntry.key;
          final entry = mapEntry.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (i > 0) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Text(
                    '模型 ${i + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.accent,
                    ),
                    onPressed: () => _removeModel(i),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: entry.nameCtrl,
                decoration: const InputDecoration(
                  labelText: '模型名称',
                  hintText: '例如: qwen-max',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: entry.urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText:
                      '例如: https://dashscope.aliyuncs.com/compatible-mode/v1',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: entry.keyCtrl,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  isDense: true,
                ),
                obscureText: true,
              ),
            ],
          );
        }),
        if (_modelEntries.isNotEmpty) const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _addNewModel,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加模型'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
          ),
        ),
      ],
    );
  }
}
