import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../database/prompt_dao.dart';
import '../models/prompt.dart';
import '../services/file_storage_service.dart';
import '../theme/app_colors.dart';
import 'markdown_editor_page.dart';
import 'prompt_manage_page.dart';

class SceneManagePage extends StatefulWidget {
  const SceneManagePage({super.key});

  @override
  State<SceneManagePage> createState() => _SceneManagePageState();
}

class _SceneManagePageState extends State<SceneManagePage> {
  final _promptDao = PromptDao.instance;
  final _fileStorage = FileStorageService();
  List<Prompt> _items = [];
  bool _isLoading = true;

  static final _config = PromptManagePageConfig.scene;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final items = await _promptDao.getAllScenes();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  void _showCreateBottomSheet() {
    final nameController = TextEditingController();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: _config.createHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.subText.withValues(alpha: 0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.subText.withValues(alpha: 0.2),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.accent,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    isDense: true,
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: 60,
                        height: 36,
                        child: ElevatedButton(
                          onPressed: () {
                            if (nameController.text.isNotEmpty) {
                              Navigator.pop(ctx);
                              _createWithName(nameController.text.trim());
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: EdgeInsets.zero,
                            elevation: 0,
                          ),
                          child: const Text('创建', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                  ),
                  autofocus: true,
                  onSubmitted: (v) {
                    if (v.isNotEmpty) {
                      Navigator.pop(ctx);
                      _createWithName(v.trim());
                    }
                  },
                ),
              ),
              Divider(
                height: 1,
                indent: 56,
                color: AppColors.subText.withValues(alpha: 0.08),
              ),
              _buildImportOption(
                icon: Icons.folder_open_outlined,
                iconColor: AppColors.accent,
                label: '导入手机文件',
                onTap: () {
                  Navigator.pop(ctx);
                  _importFile();
                },
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportOption({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createWithName(String name) async {
    final exists = await _promptDao.sceneExists(name);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_config.existsMessage)));
      }
      return;
    }

    await _fileStorage.saveScene(name, '');
    await _promptDao.createScene(name);
    _loadItems();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_config.successMessage)));
    }
  }

  Future<void> _importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final fileName = file.name;
      final nameWithoutExt = path.basenameWithoutExtension(fileName);

      final englishOnly = RegExp(r'^[a-zA-Z0-9_\-]+$');
      if (!englishOnly.hasMatch(nameWithoutExt)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件名只能包含英文字母、数字、下划线和横线')),
          );
        }
        return;
      }

      final exists = await _promptDao.sceneExists(nameWithoutExt);
      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_config.existsMessage)));
        }
        return;
      }

      String content = '';
      if (file.path != null) {
        content = await File(file.path!).readAsString();
      }

      await _fileStorage.saveScene(nameWithoutExt, content);
      await _promptDao.createScene(nameWithoutExt);
      _loadItems();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入成功: $nameWithoutExt')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }

  Future<void> _openDetail(Prompt item) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MarkdownEditorPage(prompt: item, type: _config.type),
      ),
    );

    if (result == true) {
      _loadItems();
    }
  }

  Widget _buildAvatar(Prompt item) {
    final accent = _config.accentColor;
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

  Widget _buildItemCard(Prompt item) {
    return InkWell(
      onTap: () => _openDetail(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildAvatar(item),
            const SizedBox(width: 12),
            Expanded(
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
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.subText.withValues(alpha: 0.4),
            ),
          ],
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
              _config.emptyIcon,
              size: 56,
              color: AppColors.subText.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              _config.emptyText,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.subText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _config.emptySubText,
              style: const TextStyle(fontSize: 13, color: AppColors.subText),
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
    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: AppColors.appBarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text(
          _config.label,
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
            onPressed: _showCreateBottomSheet,
            tooltip: '创建',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
