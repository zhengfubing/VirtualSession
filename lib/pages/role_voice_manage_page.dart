import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../services/file_storage_service.dart';
import '../theme/app_colors.dart';

class RoleVoiceManagePage extends StatefulWidget {
  final bool embedded;
  const RoleVoiceManagePage({super.key, this.embedded = false});

  @override
  State<RoleVoiceManagePage> createState() => _RoleVoiceManagePageState();
}

class _RoleVoiceManagePageState extends State<RoleVoiceManagePage> {
  final _db = DatabaseHelper.instance;
  final _fileStorage = FileStorageService();

  List<Map<String, dynamic>> _roles = [];
  Map<String, String> _roleVoiceMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final roles = await _db.query(
      'prompts',
      where: 'prompt_type = ?',
      whereArgs: ['roleSettingPrompt'],
    );

    final voices = await _db.getAllVoices();
    final voiceMap = <String, String>{};
    for (var v in voices) {
      voiceMap[v['name'] as String] = v['voice_name'] as String? ?? '';
    }

    setState(() {
      _roles = roles;
      _roleVoiceMap = voiceMap;
      _isLoading = false;
    });
  }

  void _openRoleVoiceEdit(String roleName) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => RoleVoiceEditPage(roleName: roleName),
          ),
        )
        .then((_) => _loadData());
  }

  Widget _buildAvatar(String roleName) {
    return FutureBuilder<String?>(
      future: _fileStorage.getRoleAvatarPath(roleName),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return CircleAvatar(
            radius: 22,
            backgroundImage: FileImage(File(snapshot.data!)),
          );
        }
        return CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.accent.withValues(alpha: 0.1),
          child: Text(
            roleName.isNotEmpty ? roleName[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2,
        ),
      );
    }

    if (_roles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 56,
              color: AppColors.subText.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无角色',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.subText,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '请先在管理中创建角色',
              style: TextStyle(fontSize: 13, color: AppColors.subText),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _roles.length,
        itemBuilder: (context, index) {
          final role = _roles[index];
          final roleName = role['file_name'] as String;
          final hasVoice = _roleVoiceMap.containsKey(roleName) &&
              (_roleVoiceMap[roleName] ?? '').isNotEmpty;
          final voiceName = _roleVoiceMap[roleName] ?? '';
          final isLast = index == _roles.length - 1;

          return Column(
            children: [
              InkWell(
                onTap: () => _openRoleVoiceEdit(roleName),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      _buildAvatar(roleName),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              roleName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hasVoice ? voiceName : '未配置音色',
                              style: TextStyle(
                                fontSize: 12,
                                color: hasVoice
                                    ? AppColors.accent.withValues(alpha: 0.7)
                                    : AppColors.subText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
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
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 60,
                  color: AppColors.subText.withValues(alpha: 0.1),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody();
    }

    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: AppColors.appBarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text(
          '角色音色',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }
}

// ==================== 音色编辑页面 ====================

class RoleVoiceEditPage extends StatefulWidget {
  final String roleName;
  const RoleVoiceEditPage({super.key, required this.roleName});

  @override
  State<RoleVoiceEditPage> createState() => _RoleVoiceEditPageState();
}

class _RoleVoiceEditPageState extends State<RoleVoiceEditPage> {
  final _db = DatabaseHelper.instance;
  final _fileStorage = FileStorageService();

  String _currentVoice = '';
  List<Map<String, dynamic>> _defaultVoices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final voiceConfig = await _db.getVoiceByName(widget.roleName);
    final defaultVoices = await _db.getAllAliyunDefaultVoices();

    setState(() {
      _currentVoice = voiceConfig?['voice_name'] as String? ?? '';
      _defaultVoices = defaultVoices;
      _isLoading = false;
    });
  }

  Future<void> _useVoice(String voiceId) async {
    await _db.saveVoice(widget.roleName, voiceId);
    setState(() => _currentVoice = voiceId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('音色已更新')),
      );
    }
  }

  void _viewVoiceDetail(Map<String, dynamic> voice) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceDetailPage(voice: voice),
      ),
    );
  }

  Widget _buildAvatar() {
    return FutureBuilder<String?>(
      future: _fileStorage.getRoleAvatarPath(widget.roleName),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return CircleAvatar(
            radius: 32,
            backgroundImage: FileImage(File(snapshot.data!)),
          );
        }
        return CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.accent.withValues(alpha: 0.1),
          child: Text(
            widget.roleName.isNotEmpty
                ? widget.roleName[0].toUpperCase()
                : '?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        );
      },
    );
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
          widget.roleName,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(
              child:
                  CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
          : Column(
              children: [
                // 角色信息头部
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  color: AppColors.headerBg,
                  child: Column(
                    children: [
                      _buildAvatar(),
                      const SizedBox(height: 10),
                      Text(
                        widget.roleName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentVoice.isEmpty
                            ? '当前未配置音色'
                            : '当前音色: $_currentVoice',
                        style: TextStyle(
                          fontSize: 13,
                          color: _currentVoice.isEmpty
                              ? AppColors.subText
                              : AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                // 音色列表
                Expanded(
                  child: _defaultVoices.isEmpty
                      ? Center(
                          child: Text(
                            '暂无可用音色',
                            style: TextStyle(
                                fontSize: 14, color: AppColors.subText),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _defaultVoices.length,
                          itemBuilder: (context, index) {
                            final v = _defaultVoices[index];
                            final id = v['id'] as String;
                            final name = v['name'] as String;
                            final desc = v['description'] as String? ?? '';
                            final scene = v['scene'] as String? ?? '';
                            final isSelected = id == _currentVoice;
                            final isLast = index == _defaultVoices.length - 1;

                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  child: Row(
                                    children: [
                                      // 音色图标
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.accent
                                                  .withValues(alpha: 0.12)
                                              : AppColors.subText
                                                  .withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.record_voice_over_outlined,
                                          size: 20,
                                          color: isSelected
                                              ? AppColors.accent
                                              : AppColors.subText,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // 音色信息
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    name,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: isSelected
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                      color: isSelected
                                                          ? AppColors.accent
                                                          : AppColors.text,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isSelected) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.accent,
                                                      borderRadius:
                                                          BorderRadius.circular(4),
                                                    ),
                                                    child: const Text(
                                                      '当前',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '$scene · $desc',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.subText,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // 按钮
                                      TextButton(
                                        onPressed: () => _useVoice(id),
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(0, 32),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                        ),
                                        child: Text(
                                          isSelected ? '已使用' : '使用',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isSelected
                                                ? AppColors.subText
                                                : AppColors.accent,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      TextButton(
                                        onPressed: () => _viewVoiceDetail(v),
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(0, 32),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                        ),
                                        child: const Text(
                                          '查看',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.subText),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isLast)
                                  Divider(
                                    height: 1,
                                    indent: 16,
                                    color: AppColors.subText.withValues(alpha: 0.1),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ==================== 音色详情页面 ====================

class VoiceDetailPage extends StatelessWidget {
  final Map<String, dynamic> voice;
  const VoiceDetailPage({super.key, required this.voice});

  @override
  Widget build(BuildContext context) {
    final id = voice['id'] as String? ?? '';
    final name = voice['name'] as String? ?? '';
    final desc = voice['description'] as String? ?? '';
    final scene = voice['scene'] as String? ?? '';
    final language = voice['language'] as String? ?? '';

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
            // 音色图标
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.record_voice_over_outlined,
                size: 36,
                color: AppColors.accent,
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
            Text(
              id,
              style: TextStyle(fontSize: 14, color: AppColors.subText),
            ),
            const SizedBox(height: 24),
            // 详情卡片
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
                  _detailRow('ID', id),
                  _detailRow('名称', name),
                  _detailRow('场景', scene.isEmpty ? '-' : scene),
                  _detailRow('描述', desc.isEmpty ? '-' : desc),
                  _detailRow('语言', language.isEmpty ? '-' : language),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
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
}
