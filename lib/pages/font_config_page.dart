import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import '../database/database_helper.dart';
import '../services/app_config_service.dart';
import '../theme/app_colors.dart';

class FontConfigPage extends StatefulWidget {
  const FontConfigPage({super.key});

  @override
  State<FontConfigPage> createState() => _FontConfigPageState();
}

class _FontConfigPageState extends State<FontConfigPage> {
  String _selectedFont = '';
  late Color _fontColor;
  List<Map<String, dynamic>> _fonts = [];
  bool _isLoading = true;
  bool _hasColorChanges = false;

  @override
  void initState() {
    super.initState();
    _selectedFont = AppConfigService.instance.fontFamily;
    _fontColor = AppConfigService.instance.fontColor;
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    final fonts = await DatabaseHelper.instance.queryAll('fonts');
    if (mounted) {
      setState(() {
        _fonts = fonts;
        _isLoading = false;
      });
    }
  }

  Future<void> _applyFont(String fontFamily) async {
    setState(() => _selectedFont = fontFamily);
    try {
      await AppConfigService.instance.set('font_family', fontFamily);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('字体已切换，应用将重启'),
            backgroundColor: Colors.green,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          Phoenix.rebirth(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static Color _normalizeColor(Color c) {
    if (c.a == 0) {
      return Color.from(alpha: 1.0 / 255, red: c.r, green: c.g, blue: c.b);
    }
    return c;
  }

  void _pickFontColor() {
    Color pickerColor = _fontColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择字体颜色'),
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
              setState(() {
                _fontColor = _normalizeColor(pickerColor);
                _hasColorChanges = true;
              });
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveFontColor() async {
    try {
      await AppConfigService.instance.set(
        'font_color',
        _fontColor.toARGB32().toString(),
      );
      setState(() => _hasColorChanges = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('字体颜色已保存，应用将重启'),
            backgroundColor: Colors.green,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          Phoenix.rebirth(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
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
          '字体',
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
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _buildPreviewCard(),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    '字体颜色',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _fontColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                  ),
                  title: const Text('文字颜色', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '#${_fontColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
                    style: const TextStyle(fontSize: 12, color: AppColors.subText),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasColorChanges)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: _saveFontColor,
                            child: Text(
                              '保存',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                  onTap: _pickFontColor,
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    '选择字体',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ...List.generate(_fonts.length, (index) {
                  final font = _fonts[index];
                  final isLast = index == _fonts.length - 1;
                  return Column(
                    children: [
                      _buildFontOption(font),
                      if (!isLast)
                        Divider(
                          height: 1,
                          indent: 16,
                          color: AppColors.subText.withValues(alpha: 0.1),
                        ),
                    ],
                  );
                }),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.subText.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppColors.subText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '字体来源',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.subText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '部分字体选自 GitHub 开源项目，地址：',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.subText,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        'https://github.com/lxgw/LxgwWenKai',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.accent,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '如有侵权请联系开发者撤销字体。',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.subText,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _buildPreviewCard() {
    final fontFamily = _selectedFont.isNotEmpty ? _selectedFont : null;
    String previewText = '天地玄黄 宇宙洪荒';
    for (final font in _fonts) {
      if (font['family_name'] == _selectedFont) {
        previewText = font['preview_text'] as String? ?? previewText;
        break;
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '字体预览',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.subText,
              fontFamily: fontFamily,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            previewText,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _fontColor,
              fontFamily: fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The quick brown fox jumps over the lazy dog.',
            style: TextStyle(
              fontSize: 14,
              color: _fontColor,
              fontFamily: fontFamily,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontOption(Map<String, dynamic> font) {
    final familyName = font['family_name'] as String;
    final displayName = font['display_name'] as String;
    final description = font['description'] as String? ?? '';
    final isSelected = _selectedFont == familyName;
    final fontFamily = familyName.isNotEmpty ? familyName : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(
          displayName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.text,
            fontFamily: fontFamily,
          ),
        ),
        subtitle: description.isNotEmpty
            ? Text(
                description,
                style: const TextStyle(fontSize: 12, color: AppColors.subText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: isSelected
            ? Icon(Icons.check_circle, size: 20, color: AppColors.accent)
            : Icon(
                Icons.radio_button_unchecked,
                size: 20,
                color: AppColors.subText.withValues(alpha: 0.4),
              ),
        onTap: isSelected ? null : () => _applyFont(familyName),
      ),
    );
  }
}
