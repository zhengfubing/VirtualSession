import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../services/file_storage_service.dart';
import '../theme/app_colors.dart';
import 'role_voice_manage_page.dart';

class VoiceSettingsPage extends StatefulWidget {
  const VoiceSettingsPage({super.key});

  @override
  State<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends State<VoiceSettingsPage> {
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
          '音色',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2,
              ),
            )
          : _roles.isEmpty
              ? Center(
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
                        '请先在设置中创建角色',
                        style: TextStyle(fontSize: 13, color: AppColors.subText),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
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
                                                ? AppColors.accent
                                                    .withValues(alpha: 0.7)
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
                ),
    );
  }
}
