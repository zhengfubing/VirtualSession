import 'dart:io';
import 'package:flutter/material.dart';
import '../services/file_storage_service.dart';
import '../services/solo_session_service.dart';
import '../theme/app_colors.dart';
import 'solo_chat_page.dart';

class SoloRoleSelectPage extends StatefulWidget {
  const SoloRoleSelectPage({super.key});

  @override
  State<SoloRoleSelectPage> createState() => _SoloRoleSelectPageState();
}

class _SoloRoleSelectPageState extends State<SoloRoleSelectPage> {
  final _fileStorage = FileStorageService();
  final _sessionService = SoloSessionService.instance;

  List<String> _allRoles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final roles = await _fileStorage.getAllRoles();
    if (mounted) {
      setState(() {
        _allRoles = roles;
        _isLoading = false;
      });
    }
  }

  Future<String?> _getAvatarPath(String roleName) async {
    return await _fileStorage.getRoleAvatarPath(roleName);
  }

  Future<void> _onRoleTap(String aiRoleName) async {
    // 检查是否已有 session
    final session = await _sessionService.getSession(aiRoleName);
    if (session != null) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SoloChatPage(
            aiRoleName: session['ai_role_name'] as String,
            userRoleName: session['user_role_name'] as String,
            scenePromptId: session['scene_prompt_id'] as String?,
          ),
        ),
      );
    } else {
      _showQuickSetup(aiRoleName);
    }
  }

  void _showQuickSetup(String aiRoleName) {
    String selectedUserRole = _allRoles.isNotEmpty ? _allRoles.first : '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            '开始与 $aiRoleName 的对话',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '我扮演的角色',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedUserRole,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _allRoles.map((r) {
                    return DropdownMenuItem(value: r, child: Text(r));
                  }).toList(),
                  onChanged: (v) {
                    setDialogState(() => selectedUserRole = v ?? '');
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                if (selectedUserRole.isEmpty) return;
                Navigator.pop(ctx);
                final session = await _sessionService.getOrCreateSession(
                  aiRoleName: aiRoleName,
                  userRoleName: selectedUserRole,
                );
                if (!mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SoloChatPage(
                      aiRoleName: session['ai_role_name'] as String,
                      userRoleName: session['user_role_name'] as String,
                      scenePromptId: session['scene_prompt_id'] as String?,
                    ),
                  ),
                );
              },
              child: const Text('确认'),
            ),
          ],
        ),
      ),
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
          '独幕',
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
          : _allRoles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 48,
                        color: AppColors.subText.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '还没有角色，请先创建角色',
                        style: TextStyle(fontSize: 14, color: AppColors.subText),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _allRoles.length,
                  itemBuilder: (context, index) {
                    final role = _allRoles[index];
                    return _buildRoleTile(role);
                  },
                ),
    );
  }

  Widget _buildRoleTile(String roleName) {
    return InkWell(
      onTap: () => _onRoleTap(roleName),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            FutureBuilder<String?>(
              future: _getAvatarPath(roleName),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return CircleAvatar(
                    radius: 24,
                    backgroundImage: FileImage(File(snapshot.data!)),
                  );
                }
                return CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                  child: Text(
                    roleName.isNotEmpty ? roleName[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roleName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FutureBuilder<Map<String, dynamic>?>(
                    future: _sessionService.getSession(roleName),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return Text(
                          '已有会话',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.accent.withValues(alpha: 0.7),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.subText.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
