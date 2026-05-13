import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/app_config_service.dart';
import '../services/theme_service.dart';

class AppColors {
  static Color get accent => ThemeService.instance.current.headerIconColor;
  static Color get text => AppConfigService.instance.fontColor;
  static const subText = Color(0xFF90A4AE);
  static const world = Color(0xFF26C6DA);
  static const worldBg = Color(0xFFE0F7FA);
  static const divider = Color(0xFFE3F2FD);

  static Color get headerBg => ThemeService.instance.current.headerBgColor;
  static Color get bodyBg => ThemeService.instance.current.pageBgColor;
  static Color get footerBg => ThemeService.instance.current.bottomBgColor;
  static Color get bottomIconColor =>
      ThemeService.instance.current.bottomIconColor;

  static Color get card => bodyBg;
  static const pink = Color(0xFFBBDEFB);
  static const peach = Color(0xFFBBDEFB);
  static Color get gradStart => bodyBg;
  static Color get gradMid => bodyBg;
  static Color get gradEnd => bodyBg;
  static Color get appBarBg => headerBg;
}

Widget buildGradientBackground({required Widget child}) => child;

/// 支持背景图片/视频的 Scaffold，当主题设置了背景时自动叠加
class ThemedScaffold extends StatefulWidget {
  final Widget? body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool? resizeToAvoidBottomInset;

  /// 当没有 bottomNavigationBar 时，是否自动为 body 添加底部安全区域
  final bool safeBottom;

  const ThemedScaffold({
    super.key,
    this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.resizeToAvoidBottomInset,
    this.safeBottom = true,
  });

  @override
  State<ThemedScaffold> createState() => _ThemedScaffoldState();
}

class _ThemedScaffoldState extends State<ThemedScaffold> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _initVideoController();
  }

  @override
  void didUpdateWidget(covariant ThemedScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当主题变化时重新初始化视频控制器
    final current = ThemeService.instance.current;
    if (current.hasVideoBackground) {
      if (_videoController == null ||
          _videoController!.dataSource != current.bgVideoPath) {
        _disposeVideoController();
        _initVideoController();
      }
    } else {
      _disposeVideoController();
    }
  }

  @override
  void dispose() {
    _disposeVideoController();
    super.dispose();
  }

  void _initVideoController() {
    final current = ThemeService.instance.current;
    if (current.hasVideoBackground) {
      final videoPath = current.bgVideoPath!;
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

  void _disposeVideoController() {
    _videoController?.dispose();
    _videoController = null;
  }

  @override
  Widget build(BuildContext context) {
    final current = ThemeService.instance.current;
    final hasVideo = current.hasVideoBackground;
    final hasImage = current.hasImageBackground;
    final hasBackground = hasVideo || hasImage;

    Widget content = widget.body ?? const SizedBox.shrink();
    // 没有底部导航栏时，添加底部安全区域防止系统导航遮盖内容
    if (widget.bottomNavigationBar == null && widget.safeBottom) {
      content = SafeArea(top: false, child: content);
    }

    // 有背景时，让 AppBar 背景透明以露出背景
    PreferredSizeWidget? effectiveAppBar = widget.appBar;
    if (hasBackground && widget.appBar != null) {
      effectiveAppBar = _TransparentAppBarWrapper(original: widget.appBar!);
    }

    final scaffold = Scaffold(
      backgroundColor: hasBackground ? Colors.transparent : AppColors.bodyBg,
      appBar: effectiveAppBar,
      body: content,
      bottomNavigationBar: widget.bottomNavigationBar,
      floatingActionButton: widget.floatingActionButton,
      drawer: widget.drawer,
      endDrawer: widget.endDrawer,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
    );

    // 背景放在 Scaffold 外层
    if (hasVideo) {
      return _buildVideoBackground(scaffold);
    } else if (hasImage) {
      return _buildImageBackground(scaffold, current.bgImagePath!);
    }
    return scaffold;
  }

  Widget _buildVideoBackground(Widget child) {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container(color: Colors.black, child: child);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // 视频层
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        ),
        // 内容层
        child,
      ],
    );
  }

  Widget _buildImageBackground(Widget child, String bgImagePath) {
    final imageProvider = bgImagePath.startsWith('assets/')
        ? AssetImage(bgImagePath) as ImageProvider
        : FileImage(File(bgImagePath));
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: imageProvider,
          fit: BoxFit.cover,
          onError: (_, __) {},
        ),
      ),
      child: child,
    );
  }
}

/// 透明 AppBar 包装器，用于显示背景图片/视频
class _TransparentAppBarWrapper extends StatelessWidget
    implements PreferredSizeWidget {
  final PreferredSizeWidget original;

  const _TransparentAppBarWrapper({required this.original});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      flexibleSpace: original,
    );
  }

  @override
  Size get preferredSize => original.preferredSize;
}
