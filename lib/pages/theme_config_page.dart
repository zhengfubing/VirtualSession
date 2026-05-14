import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../models/theme_config.dart';
import '../services/theme_service.dart';
import '../theme/app_colors.dart';

class ThemeConfigPage extends StatefulWidget {
  const ThemeConfigPage({super.key});

  @override
  State<ThemeConfigPage> createState() => _ThemeConfigPageState();
}

class _ThemeConfigPageState extends State<ThemeConfigPage> {
  late ThemeConfig _editing;
  bool _hasChanges = false;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _editing = ThemeService.instance.current;
    _initVideoController();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _initVideoController() {
    if (_editing.hasVideoBackground) {
      final videoPath = _editing.bgVideoPath!;
      // 判断是 asset 还是本地文件
      if (videoPath.startsWith('assets/')) {
        _videoController = VideoPlayerController.asset(videoPath)
          ..initialize().then((_) {
            _videoController?.setLooping(true);
            _videoController?.play();
            if (mounted) setState(() {});
          });
      } else {
        _videoController = VideoPlayerController.file(File(videoPath))
          ..initialize().then((_) {
            _videoController?.setLooping(true);
            _videoController?.play();
            if (mounted) setState(() {});
          });
      }
    }
  }

  void _updateVideoController(String? videoPath) {
    _videoController?.dispose();
    _videoController = null;
    if (videoPath != null && videoPath.isNotEmpty) {
      // 判断是 asset 还是本地文件
      if (videoPath.startsWith('assets/')) {
        _videoController = VideoPlayerController.asset(videoPath)
          ..initialize().then((_) {
            _videoController?.setLooping(true);
            _videoController?.play();
            if (mounted) setState(() {});
          });
      } else {
        _videoController = VideoPlayerController.file(File(videoPath))
          ..initialize().then((_) {
            _videoController?.setLooping(true);
            _videoController?.play();
            if (mounted) setState(() {});
          });
      }
    }
  }

  /// 完全透明时保留 RGB 信息，将 alpha=0 改为 alpha=1
  static Color _normalizeColor(Color c) {
    if (c.a == 0) {
      return Color.from(alpha: 1.0 / 255, red: c.r, green: c.g, blue: c.b);
    }
    return c;
  }

  /// 是否为 asset 资源路径
  static bool _isAsset(String? path) =>
      path != null && path.startsWith('assets/');

  /// 是否为视频文件
  static bool _isVideoFile(String? path) {
    if (path == null || path.isEmpty) return false;
    final ext = path.toLowerCase();
    return ext.endsWith('.mp4') ||
        ext.endsWith('.mov') ||
        ext.endsWith('.avi') ||
        ext.endsWith('.mkv');
  }

  void _pickColor(String title, Color current, ValueChanged<Color> onChanged) {
    Color pickerColor = current;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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
              onChanged(pickerColor);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _editing = _editing.copyWith(
          bgImagePath: picked.path,
          clearBgVideo: true,
        );
        _hasChanges = true;
      });
      _updateVideoController(null);
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _editing = _editing.copyWith(
          bgVideoPath: picked.path,
          clearBgImage: true,
        );
        _hasChanges = true;
      });
      _updateVideoController(picked.path);
    }
  }

  void _clearBackground() {
    setState(() {
      _editing = _editing.copyWith(clearBgImage: true, clearBgVideo: true);
      _hasChanges = true;
    });
    _updateVideoController(null);
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
        const SnackBar(content: Text('主题已保存'), backgroundColor: Colors.green),
      );
    }
  }

  Widget _buildColorTile(
    String title,
    Color color,
    ValueChanged<Color> onChanged,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _pickColor(title, color, (raw) {
        final c = _normalizeColor(raw);
        setState(() {
          switch (title) {
            case '主题色':
              _editing = _editing.copyWith(headerBgColor: c, bottomBgColor: c);
              break;
            case '页面背景色':
              _editing = _editing.copyWith(pageBgColor: c);
              break;
          }
          _hasChanges = true;
        });
      }),
    );
  }

  Widget _buildIconColorTile() {
    final color = _editing.headerIconColor;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
      ),
      title: const Text('图标颜色', style: TextStyle(fontSize: 14)),
      subtitle: Text(
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
        style: const TextStyle(fontSize: 12, color: AppColors.subText),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: _pickIconColor,
    );
  }

  void _pickIconColor() {
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

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: AppColors.appBarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '主题配置',
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _buildSectionTitle('颜色配置'),
          _buildColorTile('主题色', _editing.headerBgColor, (_) {}),
          _buildColorTile('页面背景色', _editing.pageBgColor, (_) {}),
          const SizedBox(height: 20),
          _buildSectionTitle('图标颜色'),
          _buildIconColorTile(),
          const SizedBox(height: 20),
          _buildSectionTitle('背景设置'),
          _buildBackgroundSection(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8, top: 4),
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

  Widget _buildBackgroundSection() {
    final hasBackground = _editing.hasBackground;
    final hasVideo = _editing.hasVideoBackground;
    final hasImage = _editing.hasImageBackground;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当前选中的背景预览
          if (hasBackground) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: hasVideo
                    ? _buildVideoPreview()
                    : hasImage
                    ? (_isAsset(_editing.bgImagePath)
                          ? Image.asset(
                              _editing.bgImagePath!,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(_editing.bgImagePath!),
                              fit: BoxFit.cover,
                            ))
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _clearBackground,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清除背景'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
          // 自定义背景选择
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickImage,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 28,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '选择图片',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: _pickVideo,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.video_library_outlined,
                          size: 28,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '选择视频',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container(
        color: Colors.grey.shade900,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: VideoPlayer(_videoController!),
    );
  }
}
