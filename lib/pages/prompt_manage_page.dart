import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../database/prompt_dao.dart';
import '../models/prompt.dart';
import '../services/file_storage_service.dart';
import '../theme/app_colors.dart';
import 'markdown_editor_page.dart';

class PromptManagePageConfig {
  final PromptDetailType type;
  final String label;
  final String promptType;
  final String createHint;
  final String existsMessage;
  final String successMessage;
  final String emptyText;
  final String emptySubText;
  final IconData emptyIcon;
  final IconData tabIcon;
  final Color accentColor;
  final Color? avatarBgColor;
  final bool showImageAvatar;

  const PromptManagePageConfig({
    required this.type,
    required this.label,
    required this.promptType,
    required this.createHint,
    required this.existsMessage,
    required this.successMessage,
    required this.emptyText,
    required this.emptySubText,
    required this.emptyIcon,
    required this.tabIcon,
    required this.accentColor,
    this.avatarBgColor,
    this.showImageAvatar = false,
  });

  static final role = PromptManagePageConfig(
    type: PromptDetailType.role,
    label: '角色',
    promptType: 'roleSettingPrompt',
    createHint: '输入角色名称',
    existsMessage: '角色已存在',
    successMessage: '角色创建成功',
    emptyText: '还没有角色哦',
    emptySubText: '点右上角 + 创建第一个角色吧',
    emptyIcon: Icons.person_outline_rounded,
    tabIcon: Icons.person_outline,
    accentColor: AppColors.accent,
    showImageAvatar: true,
  );

  static final scene = PromptManagePageConfig(
    type: PromptDetailType.scene,
    label: '场景',
    promptType: 'scenePrompt',
    createHint: '输入场景名称',
    existsMessage: '场景已存在',
    successMessage: '场景创建成功',
    emptyText: '还没有场景哦',
    emptySubText: '点右上角 + 创建第一个场景吧',
    emptyIcon: Icons.place_outlined,
    tabIcon: Icons.landscape_outlined,
    accentColor: AppColors.accent,
  );

  static const world = PromptManagePageConfig(
    type: PromptDetailType.world,
    label: '世界',
    promptType: 'world',
    createHint: '输入世界名称',
    existsMessage: '世界已存在',
    successMessage: '世界创建成功',
    emptyText: '还没有世界哦',
    emptySubText: '点右上角 + 创建第一个世界吧',
    emptyIcon: Icons.public_outlined,
    tabIcon: Icons.public_outlined,
    accentColor: AppColors.world,
    avatarBgColor: AppColors.worldBg,
  );

  static final systemPrompt = PromptManagePageConfig(
    type: PromptDetailType.systemPrompt,
    label: '提示词',
    promptType: 'systemPrompt',
    createHint: '输入提示词名称',
    existsMessage: '提示词已存在',
    successMessage: '提示词创建成功',
    emptyText: '暂无提示词',
    emptySubText: '点击右上角 + 按钮创建提示词',
    emptyIcon: Icons.description_outlined,
    tabIcon: Icons.description_outlined,
    accentColor: AppColors.accent,
  );

  static final all = [role, scene, world, systemPrompt];
}

PromptManagePageConfig configOf(String promptType) {
  return PromptManagePageConfig.all.firstWhere(
    (c) => c.promptType == promptType,
    orElse: () => PromptManagePageConfig.role,
  );
}

class PromptManagePage extends StatefulWidget {
  final bool embedded;

  const PromptManagePage({super.key, this.embedded = false});

  @override
  State<PromptManagePage> createState() => PromptManagePageState();
}

class PromptManagePageState extends State<PromptManagePage> {
  final PromptDao _promptDao = PromptDao.instance;
  final FileStorageService _fileStorage = FileStorageService();
  final ImagePicker _imagePicker = ImagePicker();
  List<Prompt> _items = [];
  Map<String, String?> _avatarPaths = {};
  bool _isLoading = true;

  void triggerCreate() => _createItem();

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      _promptDao.getAllRoles(),
      _promptDao.getAllScenes(),
      _promptDao.getAllWorlds(),
      _promptDao.getAllSystemPrompts(),
    ]);
    final allItems = [
      ...results[0],
      ...results[1],
      ...results[2],
      ...results[3],
    ];

    final avatarPaths = <String, String?>{};
    for (final item in allItems) {
      final cfg = configOf(item.promptType);
      if (cfg.showImageAvatar) {
        avatarPaths[item.fileName] = await _fileStorage.getRoleAvatarPath(
          item.fileName,
        );
      }
    }

    if (mounted) {
      setState(() {
        _items = allItems;
        _avatarPaths = avatarPaths;
        _isLoading = false;
      });
    }
  }

  Future<void> _createItem() async {
    final type = await showDialog<PromptManagePageConfig>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择类型'),
        children: PromptManagePageConfig.all.map((cfg) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, cfg),
            child: Row(
              children: [
                Icon(cfg.tabIcon, size: 20, color: cfg.accentColor),
                const SizedBox(width: 12),
                Text(cfg.label, style: const TextStyle(fontSize: 15)),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (type == null || !mounted) return;

    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        children: [
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              hintText: type.createHint,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            autofocus: true,
            onSubmitted: (v) {
              if (v.isNotEmpty) Navigator.pop(context, v.trim());
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    Navigator.pop(context, nameController.text.trim());
                  }
                },
                child: const Text('创建'),
              ),
            ],
          ),
        ],
      ),
    );

    if (name == null || !mounted) return;

    bool exists;
    switch (type.type) {
      case PromptDetailType.role:
        exists = await _promptDao.roleExists(name);
        break;
      case PromptDetailType.scene:
        exists = await _promptDao.sceneExists(name);
        break;
      case PromptDetailType.world:
        exists = await _promptDao.worldExists(name);
        break;
      case PromptDetailType.systemPrompt:
        exists = await _promptDao.systemPromptExists(name);
        break;
    }

    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(type.existsMessage)));
      }
      return;
    }

    switch (type.type) {
      case PromptDetailType.role:
        await _fileStorage.saveRole(name, '');
        await _promptDao.createRole(name);
        break;
      case PromptDetailType.scene:
        await _fileStorage.saveScene(name, '');
        await _promptDao.createScene(name);
        break;
      case PromptDetailType.world:
        await _fileStorage.saveWorld(name, '');
        await _promptDao.createWorld(name);
        break;
      case PromptDetailType.systemPrompt:
        await _fileStorage.saveSystemPrompt(name, '');
        await _promptDao.createSystemPrompt(name);
        break;
    }

    _loadItems();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(type.successMessage)));
    }
  }

  Future<void> _openDetail(Prompt item) async {
    final cfg = configOf(item.promptType);
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => MarkdownEditorPage(prompt: item, type: cfg.type),
      ),
    );

    if (result == true) {
      _loadItems();
    }
  }

  Future<void> _pickAndSetAvatar(Prompt item) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        await _fileStorage.saveRoleAvatar(item.fileName, bytes);
        final newPath = await _fileStorage.getRoleAvatarPath(item.fileName);
        setState(() {
          _avatarPaths[item.fileName] = newPath;
        });

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('头像设置成功')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置头像失败: $e')));
      }
    }
  }

  Future<void> _deleteAvatar(Prompt item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除头像'),
        content: const Text('确定要删除该角色的头像吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _fileStorage.deleteRoleAvatar(item.fileName);
      setState(() {
        _avatarPaths[item.fileName] = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('头像已删除')));
      }
    }
  }

  void _showAvatarOptions(Prompt item) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('选择头像'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSetAvatar(item);
              },
            ),
            if (_avatarPaths[item.fileName] != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('删除头像', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteAvatar(item);
                },
              ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('取消'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(Prompt item) {
    final cfg = configOf(item.promptType);
    final accent = cfg.accentColor;

    if (cfg.showImageAvatar) {
      final avatarPath = _avatarPaths[item.fileName];
      return GestureDetector(
        onTap: () => _showAvatarOptions(item),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: accent.withValues(alpha: 0.1),
          backgroundImage: avatarPath != null
              ? FileImage(File(avatarPath))
              : null,
          child: avatarPath == null
              ? Text(
                  item.fileName.isNotEmpty
                      ? item.fileName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                )
              : null,
        ),
      );
    }

    return CircleAvatar(
      radius: 22,
      backgroundColor: accent.withValues(alpha: 0.1),
      child: Text(
        item.fileName.isNotEmpty ? item.fileName[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }

  Widget _buildTypeTag(String promptType) {
    final cfg = configOf(promptType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cfg.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        cfg.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: cfg.accentColor,
        ),
      ),
    );
  }

  Future<void> _deleteItem(Prompt item) async {
    final cfg = configOf(item.promptType);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除${cfg.label} "${item.fileName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && item.id != null) {
      switch (cfg.type) {
        case PromptDetailType.role:
          await _fileStorage.deleteRole(item.fileName);
          await _promptDao.deleteRole(item.id!);
          break;
        case PromptDetailType.scene:
          await _fileStorage.deleteScene(item.fileName);
          await _promptDao.deleteScene(item.id!);
          break;
        case PromptDetailType.world:
          await _fileStorage.deleteWorld(item.fileName);
          await _promptDao.deleteWorld(item.id!);
          break;
        case PromptDetailType.systemPrompt:
          await _fileStorage.deleteSystemPrompt(item.fileName);
          await _promptDao.deleteSystemPrompt(item.id!);
          break;
      }
      _loadItems();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${cfg.label}已删除')));
      }
    }
  }

  Widget _buildItemCard(Prompt item) {
    Timer? longPressTimer;
    return GestureDetector(
      onLongPressStart: (_) {
        longPressTimer = Timer(const Duration(seconds: 5), () {
          _deleteItem(item);
        });
      },
      onLongPressEnd: (_) {
        longPressTimer?.cancel();
      },
      onLongPressCancel: () {
        longPressTimer?.cancel();
      },
      child: InkWell(
        onTap: () => _openDetail(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildAvatar(item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.fileName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildTypeTag(item.promptType),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.subText.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
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

    if (_items.isEmpty) {
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
              '暂无数据',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.subText,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '点击右上角 + 创建',
              style: TextStyle(fontSize: 13, color: AppColors.subText),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final isLast = index == _items.length - 1;
        return Column(
          children: [
            _buildItemCard(_items[index]),
            if (!isLast)
              Divider(
                height: 1,
                indent: 60,
                color: AppColors.subText.withValues(alpha: 0.1),
              ),
          ],
        );
      },
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
        title: Text(
          '管理',
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
            icon: const Icon(Icons.add_rounded, size: 26),
            color: AppColors.accent,
            onPressed: _createItem,
            tooltip: '创建',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
