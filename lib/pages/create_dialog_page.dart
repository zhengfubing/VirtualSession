import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../services/chat_state_service.dart';
import '../services/file_storage_service.dart';
import '../theme/app_colors.dart';

// ==================== 创建会话页面 ====================

class CreateChatPage extends StatefulWidget {
  final void Function(String chatId)? onCreated;
  final String modeId;

  const CreateChatPage({super.key, this.onCreated, this.modeId = 'ensemble'});

  @override
  State<CreateChatPage> createState() => _CreateChatPageState();
}

class _CreateChatPageState extends State<CreateChatPage> {
  final _nameController = TextEditingController();
  final _fileStorage = FileStorageService();

  List<String> _allRoles = [];
  List<String> _allScenes = [];

  String _selectedScene = 'empty';
  String _selectedUserRole = ''; // Solo 模式：用户扮演的角色
  String _selectedAiRole = ''; // Solo 模式：AI扮演的角色
  final List<String> _selectedRoles = []; // Ensemble 模式：多角色

  bool _isLoading = true;
  bool _isCreating = false;

  bool get _isSolo => widget.modeId == 'solo';
  String get _modeLabel => _isSolo ? '独幕' : '群像';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final roles = await _fileStorage.getAllRoles();
    final scenes = await _fileStorage.getAllScenes();
    final chats = await ChatStateService.instance.listChats();

    if (mounted) {
      setState(() {
        _allRoles = roles;
        _allScenes = scenes;
        _nameController.text = '$_modeLabel ${chats.length + 1}';
        // Solo 模式默认选中前两个角色
        if (_isSolo && roles.length >= 2) {
          _selectedUserRole = roles[0];
          _selectedAiRole = roles[1];
        } else if (_isSolo && roles.length == 1) {
          _selectedAiRole = roles[0];
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入对话名称')));
      return;
    }

    // Solo 模式校验：必须选择用户角色和AI角色
    if (_isSolo && (_selectedUserRole.isEmpty || _selectedAiRole.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择用户角色和AI角色')));
      return;
    }

    setState(() => _isCreating = true);
    try {
      final chatId = await ChatStateService.instance.createChat(
        name: name,
        scenePromptId: _selectedScene,
        roleSettingPromptIds: _isSolo ? [_selectedUserRole, _selectedAiRole] : _selectedRoles,
        senderId: _isSolo ? _selectedUserRole : 'empty',
        modeId: widget.modeId,
        roleName: _isSolo ? _selectedAiRole : '',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('会话创建成功！'),
            backgroundColor: AppColors.accent,
          ),
        );
        widget.onCreated?.call(chatId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e'), backgroundColor: AppColors.accent),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
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
          '创建$_modeLabel',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          _isCreating
              ? Padding(
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
              : IconButton(
                  icon: const Icon(Icons.check_rounded, size: 24),
                  color: AppColors.accent,
                  onPressed: _create,
                  tooltip: '创建',
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
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNameField(),
                const SizedBox(height: 4),
                _buildDropdownRow(
                  icon: Icons.landscape_outlined,
                  label: '场景',
                  value: _selectedScene,
                  items: [
                    const DropdownMenuItem(value: 'empty', child: Text('无场景')),
                    ..._allScenes.map(
                      (s) => DropdownMenuItem(value: s, child: Text(s)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedScene = v ?? 'empty'),
                ),
                if (_allRoles.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _isSolo ? _buildSoloRoleSection() : _buildRoleSection(),
                ],
              ],
            ),
    );
  }

  Widget _buildNameField() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.subText.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _nameController,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          hintText: '输入会话名称',
          hintStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.subText.withValues(alpha: 0.35),
          ),
          prefixIcon: Icon(
            Icons.edit_outlined,
            size: 20,
            color: AppColors.subText.withValues(alpha: 0.4),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 14,
          ),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildDropdownRow({
    required IconData icon,
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.subText),
          const SizedBox(width: 12),
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
          ),
          Expanded(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              underline: const SizedBox(),
              icon: Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.subText.withValues(alpha: 0.4),
              ),
              style: const TextStyle(fontSize: 14, color: AppColors.subText),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_outlined, size: 18, color: AppColors.subText),
              const SizedBox(width: 12),
              Text(
                '参与角色',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allRoles.map((role) {
              final selected = _selectedRoles.contains(role);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedRoles.remove(role);
                    } else {
                      _selectedRoles.add(role);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppColors.accent.withValues(alpha: 0.4)
                          : AppColors.subText.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected) ...[
                        Icon(Icons.check, size: 14, color: AppColors.accent),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        role,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? AppColors.accent : AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSoloRoleSection() {
    final userAvailable = _allRoles.where((r) => r != _selectedAiRole).toList();
    final aiAvailable = _allRoles.where((r) => r != _selectedUserRole).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 18, color: AppColors.subText),
              const SizedBox(width: 12),
              Text(
                'AI 扮演',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: aiAvailable.map((role) {
              final selected = _selectedAiRole == role;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedAiRole = role);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppColors.accent.withValues(alpha: 0.4)
                          : AppColors.subText.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected) ...[
                        Icon(Icons.check, size: 14, color: AppColors.accent),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        role,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? AppColors.accent : AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.person_outline, size: 18, color: AppColors.subText),
              const SizedBox(width: 12),
              Text(
                '我扮演',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: userAvailable.map((role) {
              final selected = _selectedUserRole == role;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedUserRole = role);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppColors.accent.withValues(alpha: 0.4)
                          : AppColors.subText.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected) ...[
                        Icon(Icons.check, size: 14, color: AppColors.accent),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        role,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? AppColors.accent : AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ==================== 创建世界对话页面 ====================

class CreateWorldPage extends StatefulWidget {
  final void Function(String chatId)? onCreated;

  const CreateWorldPage({super.key, this.onCreated});

  @override
  State<CreateWorldPage> createState() => _CreateWorldPageState();
}

class _CreateWorldPageState extends State<CreateWorldPage> {
  final _nameController = TextEditingController();
  final _fileStorage = FileStorageService();
  final _db = DatabaseHelper.instance;
  static const _uuid = Uuid();

  List<String> _allRoles = [];
  List<String> _allScenes = [];
  List<String> _allWorlds = [];

  String _selectedWorld = '';
  String _currentScene = '';
  List<String> _sceneRoles = [];
  final Map<String, String> _roleLocations = {};

  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final roles = await _fileStorage.getAllRoles();
    final scenes = await _fileStorage.getAllScenes();
    final worlds = await _fileStorage.getAllWorlds();

    final worldChats = await _db.query(
      'world_chats',
      where: 'deleted_at IS NULL',
    );

    if (mounted) {
      setState(() {
        _allRoles = roles;
        _allScenes = scenes;
        _allWorlds = worlds;

        _nameController.text = '世界对话 ${worldChats.length + 1}';

        if (worlds.isNotEmpty) _selectedWorld = worlds.first;
        if (scenes.isNotEmpty) _currentScene = scenes.first;
        _sceneRoles = List.from(roles);
        for (var r in roles) {
          _roleLocations[r] = _currentScene;
        }

        _isLoading = false;
      });
    }
  }

  void _onSceneChanged(String? scene) {
    if (scene == null) return;
    setState(() {
      _currentScene = scene;
      for (var r in _sceneRoles) {
        _roleLocations[r] = scene;
      }
    });
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入对话名称')));
      return;
    }

    if (_selectedWorld.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择一个世界场景')));
      return;
    }

    setState(() => _isCreating = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      final chatId = _uuid.v4();
      await _db.insert('world_chats', {
        'id': chatId,
        'name': name,
        'world_scene_id': _selectedWorld,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      });
      for (final role in _sceneRoles) {
        await _db.insert('world_chat_roles', {
          'id': _uuid.v4(),
          'world_chat_id': chatId,
          'role_name': role,
          'scene_name': _roleLocations[role] ?? _currentScene,
          'created_at': now,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('世界对话创建成功！'),
            backgroundColor: AppColors.accent,
          ),
        );
        widget.onCreated?.call(chatId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e'), backgroundColor: AppColors.accent),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
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
          '创建世界',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          _isCreating
              ? Padding(
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
              : IconButton(
                  icon: const Icon(Icons.check_rounded, size: 24),
                  color: AppColors.accent,
                  onPressed: _create,
                  tooltip: '创建',
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
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNameField(),
                const SizedBox(height: 4),
                _buildDropdownRow(
                  icon: Icons.public_outlined,
                  label: '世界',
                  value: _selectedWorld.isEmpty ? null : _selectedWorld,
                  items: _allWorlds.isEmpty
                      ? null
                      : _allWorlds
                          .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                          .toList(),
                  onChanged: (v) => setState(() => _selectedWorld = v ?? ''),
                  emptyText: '暂无世界',
                ),
                _buildDropdownRow(
                  icon: Icons.theater_comedy_outlined,
                  label: '场景',
                  value: _currentScene.isEmpty ? null : _currentScene,
                  items: _allScenes.isEmpty
                      ? null
                      : _allScenes
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                  onChanged: _onSceneChanged,
                  emptyText: '暂无场景',
                ),
                if (_allRoles.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildRoleSection(),
                ],
              ],
            ),
    );
  }

  Widget _buildNameField() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.subText.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _nameController,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          hintText: '输入世界对话名称',
          hintStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.subText.withValues(alpha: 0.35),
          ),
          prefixIcon: Icon(
            Icons.edit_outlined,
            size: 20,
            color: AppColors.subText.withValues(alpha: 0.4),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 14,
          ),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildDropdownRow({
    required IconData icon,
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>>? items,
    required void Function(String?) onChanged,
    String? emptyText,
  }) {
    if (items == null || items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.subText),
            const SizedBox(width: 12),
            SizedBox(
              width: 56,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ),
            Expanded(
              child: Text(
                emptyText ?? '暂无数据',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.subText.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.subText),
          const SizedBox(width: 12),
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
          ),
          Expanded(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              underline: const SizedBox(),
              icon: Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.subText.withValues(alpha: 0.4),
              ),
              style: const TextStyle(fontSize: 14, color: AppColors.subText),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_outlined, size: 18, color: AppColors.subText),
              const SizedBox(width: 12),
              Text(
                '场景角色',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allRoles.map((role) {
              final selected = _sceneRoles.contains(role);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _sceneRoles.remove(role);
                      _roleLocations.remove(role);
                    } else {
                      _sceneRoles.add(role);
                      _roleLocations[role] = _currentScene;
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppColors.accent.withValues(alpha: 0.4)
                          : AppColors.subText.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected) ...[
                        Icon(Icons.check, size: 14, color: AppColors.accent),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        role,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? AppColors.accent : AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_sceneRoles.length > 1) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: AppColors.subText,
                ),
                const SizedBox(width: 12),
                Text(
                  '分配角色位置',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._buildLocationList(),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildLocationList() {
    return _sceneRoles.map((role) {
      final currentRoleScene = _roleLocations[role] ?? _currentScene;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.accent.withValues(alpha: 0.1),
              child: Text(
                role[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                role,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: currentRoleScene.isEmpty ? null : currentRoleScene,
              underline: const SizedBox(),
              isDense: true,
              style: const TextStyle(fontSize: 13, color: AppColors.subText),
              icon: Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.subText.withValues(alpha: 0.4),
              ),
              items: _allScenes
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) {
                setState(() => _roleLocations[role] = v ?? '');
              },
            ),
          ],
        ),
      );
    }).toList();
  }
}
