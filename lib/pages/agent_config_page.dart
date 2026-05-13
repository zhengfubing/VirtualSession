import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/ai_model.dart';
import '../services/app_config_service.dart';
import '../theme/app_colors.dart';

class AgentConfigPage extends StatefulWidget {
  const AgentConfigPage({super.key});

  @override
  State<AgentConfigPage> createState() => _AgentConfigPageState();
}

class _AgentConfigPageState extends State<AgentConfigPage> {
  final _config = AppConfigService.instance;
  final _db = DatabaseHelper.instance;

  List<String> _modelNames = [];
  String _modelChat = '';
  String _modelCompression = '';
  String _modelMemory = '';

  @override
  void initState() {
    super.initState();
    _modelChat = _config.agentModelChat;
    _modelCompression = _config.agentModelCompression;
    _modelMemory = _config.soloMemoryModel;
    _loadModelNames();
  }

  Future<void> _loadModelNames() async {
    final models = await _db.getAllModels();
    if (mounted) {
      setState(() {
        _modelNames = models.map((m) => AIModel.fromMap(m).name).toList();
      });
    }
  }

  Future<void> _save() async {
    await _config.set('agent_model_chat', _modelChat);
    await _config.set('agent_model_compression', _modelCompression);
    await _config.set('solo_memory_model', _modelMemory);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('智能体配置已保存')),
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
          '智能体配置',
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
              const SizedBox(height: 14),
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
}
