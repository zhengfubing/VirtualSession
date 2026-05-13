import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/theme_config.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService instance = ThemeService._();
  ThemeService._();

  final _db = DatabaseHelper.instance;
  ThemeConfig _current = ThemeConfig.defaultTheme;

  ThemeConfig get current => _current;

  Future<void> load() async {
    final row = await _db.getActiveTheme();
    if (row != null) {
      _current = ThemeConfig.fromMap(row);
    } else {
      final all = await _db.getAllThemes();
      if (all.isNotEmpty) {
        _current = ThemeConfig.fromMap(all.first);
      }
    }
  }

  /// 保存主题（新建或更新），返回带有正确 id 的 ThemeConfig，并设为激活主题
  Future<ThemeConfig> saveTheme(ThemeConfig theme) async {
    ThemeConfig saved;
    if (theme.id != null) {
      await _db.updateTheme(theme.id!, theme.toMap());
      saved = theme;
    } else {
      final id = await _db.createTheme(theme.toMap());
      saved = theme.copyWith(id: id);
    }
    await _db.setActiveTheme(saved.id!);
    _current = saved.copyWith(isActive: true);
    notifyListeners();
    return _current;
  }

  Future<void> deleteTheme(int id) async {
    await _db.deleteTheme(id);
    if (_current.id == id) {
      await load();
      notifyListeners();
    }
  }

  Future<void> resetToDefault() async {
    _current = ThemeConfig.defaultTheme;
    notifyListeners();
  }
}
