import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../theme/app_colors.dart';

class VoiceManagePage extends StatefulWidget {
  const VoiceManagePage({super.key});

  @override
  State<VoiceManagePage> createState() => _VoiceManagePageState();
}

class _VoiceManagePageState extends State<VoiceManagePage> {
  final _db = DatabaseHelper.instance;

  List<Map<String, dynamic>> _voices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final voices = await _db.getAllAliyunDefaultVoices();
    setState(() {
      _voices = voices;
      _isLoading = false;
    });
  }

  Future<void> _deleteVoice(Map<String, dynamic> voice) async {
    final id = voice['id'] as String;
    final name = voice['name'] as String;
    final isCustom = (voice['is_custom'] as int? ?? 0) == 1;

    if (!isCustom) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('内置音色不可删除')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除音色'),
        content: Text('确定要删除音色「$name」($id) 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _db.deleteCustomVoice(id);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('音色已删除'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _addVoice() async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final sceneCtrl = TextEditingController();
    String language = 'zh';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加音色'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(
                    labelText: '音色 ID',
                    hintText: '例如: my_voice_01',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '音色名称',
                    hintText: '例如: 我的音色',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sceneCtrl,
                  decoration: const InputDecoration(
                    labelText: '场景',
                    hintText: '例如: 通用 / 方言 / 童声',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: '描述',
                    hintText: '音色描述',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: language,
                  decoration: const InputDecoration(
                    labelText: '语言',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'zh', child: Text('中文')),
                    DropdownMenuItem(value: 'en', child: Text('英文')),
                    DropdownMenuItem(value: 'ja', child: Text('日文')),
                    DropdownMenuItem(value: 'ko', child: Text('韩文')),
                    DropdownMenuItem(value: 'yue', child: Text('粤语')),
                    DropdownMenuItem(value: 'wuu', child: Text('吴语')),
                    DropdownMenuItem(value: 'other', child: Text('其他')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => language = v);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    final id = idCtrl.text.trim();
    final name = nameCtrl.text.trim();

    if (id.isEmpty || name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音色 ID 和名称不能为空'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // Check for duplicate ID
    final exists = _voices.any((v) => v['id'] == id);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('音色 ID「$id」已存在'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    await _db.addCustomVoice({
      'id': id,
      'name': name,
      'description': descCtrl.text.trim(),
      'scene': sceneCtrl.text.trim(),
      'language': language,
    });

    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('音色添加成功'), backgroundColor: Colors.green),
      );
    }
  }

  void _viewVoice(Map<String, dynamic> voice) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VoiceDetailPage(voice: voice),
      ),
    );
  }

  String _languageLabel(String code) {
    switch (code) {
      case 'zh':
        return '中文';
      case 'en':
        return '英文';
      case 'ja':
        return '日文';
      case 'ko':
        return '韩文';
      case 'yue':
        return '粤语';
      case 'wuu':
        return '吴语';
      default:
        return code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final customVoices =
        _voices.where((v) => (v['is_custom'] as int? ?? 0) == 1).toList();
    final builtinVoices =
        _voices.where((v) => (v['is_custom'] as int? ?? 0) == 0).toList();

    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: AppColors.appBarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text(
          '音色管理',
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
            icon: Icon(Icons.add, color: AppColors.accent),
            onPressed: _addVoice,
            tooltip: '添加音色',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2,
              ),
            )
          : _voices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.music_off_outlined,
                        size: 56,
                        color: AppColors.subText.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '暂无音色',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.subText,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (customVoices.isNotEmpty) ...[
                        _buildSectionHeader('自定义音色', customVoices.length),
                        ...customVoices.map((v) => _buildVoiceTile(v)),
                      ],
                      if (builtinVoices.isNotEmpty) ...[
                        _buildSectionHeader(
                            '内置音色', builtinVoices.length),
                        ...builtinVoices.map((v) => _buildVoiceTile(v)),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildVoiceTile(Map<String, dynamic> voice) {
    final id = voice['id'] as String;
    final name = voice['name'] as String;
    final scene = voice['scene'] as String? ?? '';
    final language = voice['language'] as String? ?? 'zh';
    final isCustom = (voice['is_custom'] as int? ?? 0) == 1;

    return Dismissible(
      key: Key('voice_$id'),
      direction:
          isCustom ? DismissDirection.endToStart : DismissDirection.none,
      confirmDismiss: (_) async {
        await _deleteVoice(voice);
        return false; // _deleteVoice handles removal via _loadData
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: InkWell(
        onTap: () => _viewVoice(voice),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isCustom
                      ? Colors.orange.withValues(alpha: 0.1)
                      : AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isCustom ? Icons.person_add_alt_outlined : Icons.record_voice_over_outlined,
                  size: 20,
                  color: isCustom ? Colors.orange : AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCustom) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '自定义',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [id, if (scene.isNotEmpty) scene, _languageLabel(language)]
                          .where((e) => e.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(fontSize: 12, color: AppColors.subText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isCustom)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.withValues(alpha: 0.6)),
                  onPressed: () => _deleteVoice(voice),
                  tooltip: '删除',
                ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.subText.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 音色详情页面 ====================

class _VoiceDetailPage extends StatelessWidget {
  final Map<String, dynamic> voice;
  const _VoiceDetailPage({required this.voice});

  @override
  Widget build(BuildContext context) {
    final id = voice['id'] as String? ?? '';
    final name = voice['name'] as String? ?? '';
    final desc = voice['description'] as String? ?? '';
    final scene = voice['scene'] as String? ?? '';
    final language = voice['language'] as String? ?? '';
    final isCustom = (voice['is_custom'] as int? ?? 0) == 1;

    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: AppColors.appBarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text(
          '音色详情',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isCustom
                    ? Colors.orange.withValues(alpha: 0.1)
                    : AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCustom ? Icons.person_add_alt_outlined : Icons.record_voice_over_outlined,
                size: 36,
                color: isCustom ? Colors.orange : AppColors.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  id,
                  style: TextStyle(fontSize: 14, color: AppColors.subText),
                ),
                if (isCustom) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '自定义',
                      style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.headerBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('ID', id, context),
                  _detailRow('名称', name, context),
                  _detailRow('场景', scene.isEmpty ? '-' : scene, context),
                  _detailRow('描述', desc.isEmpty ? '-' : desc, context),
                  _detailRow('语言', _languageLabel(language), context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.subText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _languageLabel(String code) {
    switch (code) {
      case 'zh':
        return '中文';
      case 'en':
        return '英文';
      case 'ja':
        return '日文';
      case 'ko':
        return '韩文';
      case 'yue':
        return '粤语';
      case 'wuu':
        return '吴语';
      default:
        return code;
    }
  }
}
