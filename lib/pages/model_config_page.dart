import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/ai_model.dart';
import '../services/app_config_service.dart';
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
  })  : nameCtrl = TextEditingController(text: name),
        urlCtrl = TextEditingController(text: baseUrl),
        keyCtrl = TextEditingController(text: apiKey);

  void dispose() {
    nameCtrl.dispose();
    urlCtrl.dispose();
    keyCtrl.dispose();
  }
}

class ModelConfigPage extends StatefulWidget {
  const ModelConfigPage({super.key});

  @override
  State<ModelConfigPage> createState() => _ModelConfigPageState();
}

class _ModelConfigPageState extends State<ModelConfigPage> {
  final _config = AppConfigService.instance;
  final _db = DatabaseHelper.instance;

  final _masterKeyCtrl = TextEditingController();

  final List<_ModelEntry> _modelEntries = [];

  final _ttsApiKeyCtrl = TextEditingController();
  final _ttsBaseUrlCtrl = TextEditingController();
  final _ttsModelCtrl = TextEditingController();
  final _ttsVoiceCtrl = TextEditingController();
  final _ttsLanguageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _masterKeyCtrl.addListener(_onMasterKeyChanged);
    _loadModelEntries();
    _loadTtsConfig();
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
    super.dispose();
  }

  Future<void> _save() async {
    await _db.setTtsConfig('tts_api_key', _ttsApiKeyCtrl.text.trim());

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

    await Future.wait([
      _db.setTtsConfig('tts_base_url', _ttsBaseUrlCtrl.text.trim()),
      _db.setTtsConfig('tts_model', _ttsModelCtrl.text.trim()),
      _db.setTtsConfig('tts_voice', _ttsVoiceCtrl.text.trim()),
      _db.setTtsConfig('tts_language', _ttsLanguageCtrl.text.trim()),
    ]);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模型配置已保存')),
      );
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
          '模型配置',
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
            onPressed: _save,
            tooltip: '保存',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
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

          _sectionTitle('模型管理', Icons.storage_outlined),
          const SizedBox(height: 10),
          _card(children: [_buildModelSection()]),
        ],
      ),
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
}
