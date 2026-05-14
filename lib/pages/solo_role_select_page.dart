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
  String? _selectedAiRole;
  String? _selectedUserRole;
  bool _isLoading = true;
  bool _isCreating = false;

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
        if (roles.length >= 2) {
          _selectedUserRole = roles[0];
          _selectedAiRole = roles[1];
        } else if (roles.length == 1) {
          _selectedAiRole = roles.first;
        }
        _isLoading = false;
      });
    }
  }

  Future<String?> _getAvatarPath(String roleName) async {
    return await _fileStorage.getRoleAvatarPath(roleName);
  }

  /// Roles available for AI selection (exclude user-selected role)
  List<String> get _aiAvailableRoles =>
      _allRoles.where((r) => r != _selectedUserRole).toList();

  /// Roles available for User selection (exclude ai-selected role)
  List<String> get _userAvailableRoles =>
      _allRoles.where((r) => r != _selectedAiRole).toList();

  Future<void> _onConfirm() async {
    if (_selectedAiRole == null || _selectedUserRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择AI角色和用户角色')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final session = await _sessionService.getOrCreateSession(
        aiRoleName: _selectedAiRole!,
        userRoleName: _selectedUserRole!,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SoloChatPage(
            aiRoleName: session['ai_role_name'] as String,
            userRoleName: session['user_role_name'] as String,
            scenePromptId: session['scene_prompt_id'] as String?,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
        setState(() => _isCreating = false);
      }
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
          '创建 Solo',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isCreating)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check_rounded, size: 24),
              color: AppColors.accent,
              onPressed: _onConfirm,
              tooltip: '确定',
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
                        '还没有角色，请先在设置中创建角色',
                        style: TextStyle(fontSize: 14, color: AppColors.subText),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _buildSectionHeader('AI 扮演', Icons.smart_toy_outlined),
                    ..._aiAvailableRoles.map((role) => _buildRoleTile(
                          role,
                          isSelected: role == _selectedAiRole,
                          onTap: () => setState(() => _selectedAiRole = role),
                        )),
                    const SizedBox(height: 16),
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.subText.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 8),
                    _buildSectionHeader('我扮演', Icons.person_outline),
                    ..._userAvailableRoles.map((role) => _buildRoleTile(
                          role,
                          isSelected: role == _selectedUserRole,
                          onTap: () => setState(() => _selectedUserRole = role),
                        )),
                    const SizedBox(height: 16),
                  ],
                ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleTile(
    String roleName, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  backgroundColor: isSelected
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.accent.withValues(alpha: 0.08),
                  child: Text(
                    roleName.isNotEmpty ? roleName[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.subText,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                roleName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppColors.accent : AppColors.text,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, size: 22, color: AppColors.accent)
            else
              Icon(
                Icons.radio_button_unchecked,
                size: 22,
                color: AppColors.subText.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );
  }
}
