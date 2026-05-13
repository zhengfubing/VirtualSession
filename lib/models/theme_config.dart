import 'dart:ui';

class ThemeConfig {
  final int? id;
  final String name;
  final Color headerBgColor;
  final Color headerIconColor;
  final Color bottomBgColor;
  final Color bottomIconColor;
  final Color pageBgColor;
  final String? bgImagePath;
  final String? bgVideoPath;
  final bool isActive;

  const ThemeConfig({
    this.id,
    required this.name,
    required this.headerBgColor,
    required this.headerIconColor,
    required this.bottomBgColor,
    required this.bottomIconColor,
    required this.pageBgColor,
    this.bgImagePath,
    this.bgVideoPath,
    this.isActive = false,
  });

  static const defaultTheme = ThemeConfig(
    name: '默认主题',
    headerBgColor: Color(0xFFE3F2FD),
    headerIconColor: Color(0xFF2979FF),
    bottomBgColor: Color(0xFFE3F2FD),
    bottomIconColor: Color(0xFF2979FF),
    pageBgColor: Color(0xFFFFFFFF),
  );

  ThemeConfig copyWith({
    int? id,
    String? name,
    Color? headerBgColor,
    Color? headerIconColor,
    Color? bottomBgColor,
    Color? bottomIconColor,
    Color? pageBgColor,
    String? bgImagePath,
    String? bgVideoPath,
    bool? isActive,
    bool clearBgImage = false,
    bool clearBgVideo = false,
  }) {
    return ThemeConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      headerBgColor: headerBgColor ?? this.headerBgColor,
      headerIconColor: headerIconColor ?? this.headerIconColor,
      bottomBgColor: bottomBgColor ?? this.bottomBgColor,
      bottomIconColor: bottomIconColor ?? this.bottomIconColor,
      pageBgColor: pageBgColor ?? this.pageBgColor,
      bgImagePath: clearBgImage ? null : (bgImagePath ?? this.bgImagePath),
      bgVideoPath: clearBgVideo ? null : (bgVideoPath ?? this.bgVideoPath),
      isActive: isActive ?? this.isActive,
    );
  }

  static Color _restoreColor(int value) {
    final c = Color(value);
    if (c.a == 0) {
      return Color(value | 0x01000000);
    }
    return c;
  }

  factory ThemeConfig.fromMap(Map<String, dynamic> map) {
    return ThemeConfig(
      id: map['id'] as int?,
      name: map['name'] as String,
      headerBgColor: _restoreColor(map['header_bg_color'] as int),
      headerIconColor: _restoreColor(map['header_icon_color'] as int),
      bottomBgColor: _restoreColor(map['bottom_bg_color'] as int),
      bottomIconColor: _restoreColor(map['bottom_icon_color'] as int),
      pageBgColor: _restoreColor(map['page_bg_color'] as int),
      bgImagePath: map['bg_image_path'] as String?,
      bgVideoPath: map['bg_video_path'] as String?,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'header_bg_color': headerBgColor.toARGB32(),
      'header_icon_color': headerIconColor.toARGB32(),
      'bottom_bg_color': bottomBgColor.toARGB32(),
      'bottom_icon_color': bottomIconColor.toARGB32(),
      'page_bg_color': pageBgColor.toARGB32(),
      'bg_image_path': bgImagePath,
      'bg_video_path': bgVideoPath,
      'is_active': isActive ? 1 : 0,
    };
  }

  bool get hasVideoBackground => bgVideoPath != null && bgVideoPath!.isNotEmpty;
  bool get hasImageBackground => bgImagePath != null && bgImagePath!.isNotEmpty;
  bool get hasBackground => hasVideoBackground || hasImageBackground;
}
