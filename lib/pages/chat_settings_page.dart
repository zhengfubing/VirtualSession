import 'package:flutter/material.dart';
import '../services/app_config_service.dart';
import '../services/file_storage_service.dart';
import '../theme/app_colors.dart';

class ChatSettingsPage extends StatefulWidget {
  const ChatSettingsPage({super.key});

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  final _config = AppConfigService.instance;
  final _fileStorage = FileStorageService();

  bool _enableThinking = false;
  bool _enableSearch = false;
  String _defaultSystemPromptId = '';
  String _worldchatSystemPromptId = '';
  String _soloSystemPromptId = '';
  List<String> _systemPromptNames = [];

  @override
  void initState() {
    super.initState();
    _enableThinking = _config.enableThinking;
    _enableSearch = _config.enableSearch;
    _defaultSystemPromptId = _config.defaultSystemPromptId;
    _worldchatSystemPromptId = _config.worldchatSystemPromptId;
    _soloSystemPromptId = _config.soloSystemPromptId;
    _loadSystemPromptNames();
  }

  Future<void> _loadSystemPromptNames() async {
    final names = await _fileStorage.getAllSystemPrompts();
    if (mounted) {
      setState(() {
        _systemPromptNames = names;
      });
    }
  }

  Future<void> _save() async {
    await _config.set('enable_thinking', _enableThinking.toString());
    await _config.set('enable_search', _enableSearch.toString());
    await _config.set('default_system_prompt_id', _defaultSystemPromptId);
    await _config.set('worldchat_system_prompt_id', _worldchatSystemPromptId);
    await _config.set('solo_system_prompt_id', _soloSystemPromptId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('聊天设置已保存')),
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
          '聊天设置',
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
        ],
      ),
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
}
