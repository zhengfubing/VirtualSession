import 'package:flutter/material.dart';

import '../services/app_config_service.dart';
import '../theme/app_colors.dart';

class MemoryCompressionPage extends StatefulWidget {
  const MemoryCompressionPage({super.key});

  @override
  State<MemoryCompressionPage> createState() => _MemoryCompressionPageState();
}

class _MemoryCompressionPageState extends State<MemoryCompressionPage> {
  final _config = AppConfigService.instance;

  double _recentKeep = 30;
  double _aBatch = 15;
  double _memoryRounds = 5;
  double _memoryRecentKeep = 5;
  double _memoryMaxContext = 20;
  double _maxHistoryRounds = 30;

  @override
  void initState() {
    super.initState();
    _recentKeep = _config.compressionRecentKeep.toDouble();
    _aBatch = _config.compressionABatch.toDouble();
    _memoryRounds = _config.soloMemoryRounds.toDouble();
    _memoryRecentKeep = _config.soloMemoryRecentKeep.toDouble();
    _memoryMaxContext = _config.soloMemoryMaxContext.toDouble();
    _maxHistoryRounds = _config.soloMaxHistoryRounds.toDouble();
  }

  Future<void> _save() async {
    await _config.set('compression_recent_keep', _recentKeep.round().toString());
    await _config.set('compression_a_batch', _aBatch.round().toString());
    await _config.set('solo_memory_rounds', _memoryRounds.round().toString());
    await _config.set('solo_memory_recent_keep', _memoryRecentKeep.round().toString());
    await _config.set('solo_memory_max_context', _memoryMaxContext.round().toString());
    await _config.set('solo_max_history_rounds', _maxHistoryRounds.round().toString());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('记忆压缩配置已保存')));
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
          '记忆压缩',
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
          _sectionTitle('压缩配置', Icons.compress_outlined),
          const SizedBox(height: 10),
          _card(
            children: [
              _slider(
                label: '保留原始消息数',
                value: _recentKeep,
                min: 0,
                max: 100,
                divisions: 100,
                onChanged: (v) => setState(() => _recentKeep = v),
              ),
              const SizedBox(height: 14),
              _slider(
                label: '每次压缩源消息数',
                value: _aBatch,
                min: 1,
                max: 50,
                divisions: 49,
                onChanged: (v) => setState(() => _aBatch = v),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _sectionTitle('Solo 记忆配置', Icons.memory_outlined),
          const SizedBox(height: 10),
          _card(
            children: [
              _slider(
                label: '记忆提取轮次',
                value: _memoryRounds,
                min: 2,
                max: 20,
                divisions: 18,
                onChanged: (v) => setState(() => _memoryRounds = v),
                hint: '每累计足够的压缩摘要后触发一次记忆提取，值越小提取越频繁。',
              ),
              const SizedBox(height: 14),
              _slider(
                label: '记忆保留最近摘要数',
                value: _memoryRecentKeep,
                min: 0,
                max: 20,
                divisions: 20,
                onChanged: (v) => setState(() => _memoryRecentKeep = v),
                hint: '最新的 N 条摘要不会被记忆消费，仍作为活跃摘要参与上下文。',
              ),
              const SizedBox(height: 14),
              _slider(
                label: '上下文最大 memory_ref 数',
                value: _memoryMaxContext,
                min: 0,
                max: 50,
                divisions: 50,
                onChanged: (v) => setState(() => _memoryMaxContext = v),
                hint: '超过上限后，最老的 memory_ref 会从活跃上下文中移除。',
              ),
              const SizedBox(height: 14),
              _slider(
                label: '远古记忆轮次上限',
                value: _maxHistoryRounds,
                min: 0,
                max: 200,
                divisions: 200,
                onChanged: (v) => setState(() => _maxHistoryRounds = v),
                hint: '被挤出活跃上下文的记忆会按这个上限折算为"远古记忆"补充到系统提示词。',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? hint,
  }) {
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
              '${value.round()}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppColors.accent,
          onChanged: onChanged,
        ),
        if (hint != null) ...[
          Text(
            hint,
            style: TextStyle(fontSize: 11, color: AppColors.subText),
          ),
        ],
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
