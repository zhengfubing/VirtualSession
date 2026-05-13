import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/theme_config.dart';
import '../services/theme_service.dart';
import '../theme/app_colors.dart';

class IconConfigPage extends StatefulWidget {
  const IconConfigPage({super.key});

  @override
  State<IconConfigPage> createState() => _IconConfigPageState();
}

class _IconConfigPageState extends State<IconConfigPage> {
  late ThemeConfig _editing;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _editing = ThemeService.instance.current;
  }

  static Color _normalizeColor(Color c) {
    if (c.a == 0) {
      return Color.from(alpha: 1.0 / 255, red: c.r, green: c.g, blue: c.b);
    }
    return c;
  }

  void _pickColor() {
    Color pickerColor = _editing.headerIconColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择图标颜色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (c) => pickerColor = c,
            enableAlpha: true,
            displayThumbColor: true,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final c = _normalizeColor(pickerColor);
              setState(() {
                _editing = _editing.copyWith(
                  headerIconColor: c,
                  bottomIconColor: c,
                );
                _hasChanges = true;
              });
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final service = ThemeService.instance;
    final saved = await service.saveTheme(_editing);
    setState(() {
      _editing = saved;
      _hasChanges = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('图标颜色已保存'),
          backgroundColor: Colors.green,
        ),
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
        title: Text(
          '图标',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.accent),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _save,
              child: Text(
                '保存',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionTitle('全局图标颜色'),
          const SizedBox(height: 4),
          _buildColorTile(),
          const SizedBox(height: 24),
          _buildPreviewSection(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildColorTile() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _editing.headerIconColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
      ),
      title: const Text('图标颜色', style: TextStyle(fontSize: 14)),
      subtitle: Text(
        '#${_editing.headerIconColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
        style: const TextStyle(fontSize: 12, color: AppColors.subText),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: _pickColor,
    );
  }

  Widget _buildPreviewSection() {
    final color = _editing.headerIconColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.subText.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '图标预览',
            style: TextStyle(fontSize: 13, color: AppColors.subText),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 16,
            children: [
              _previewIcon(Icons.home_outlined, '首页', color),
              _previewIcon(Icons.chat_bubble_outline, '聊天', color),
              _previewIcon(Icons.person_outline, '角色', color),
              _previewIcon(Icons.settings_outlined, '设置', color),
              _previewIcon(Icons.search, '搜索', color),
              _previewIcon(Icons.add, '添加', color),
              _previewIcon(Icons.edit_outlined, '编辑', color),
              _previewIcon(Icons.share_outlined, '分享', color),
              _previewIcon(Icons.delete_outline, '删除', color),
              _previewIcon(Icons.save_outlined, '保存', color),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewIcon(IconData icon, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 28, color: color),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.subText)),
      ],
    );
  }
}
