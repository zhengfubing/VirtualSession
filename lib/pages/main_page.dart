import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import '../theme/app_colors.dart';
import '../database/database_helper.dart';

import 'agent_config_page.dart';
import 'chat_settings_page.dart';
import 'memory_compression_page.dart';
import 'model_config_page.dart';
import 'role_manage_page.dart';
import 'scene_manage_page.dart';
import 'world_manage_page.dart';
import 'voice_settings_page.dart';
import 'theme_config_page.dart';
import 'font_config_page.dart';
import 'icon_config_page.dart';
import 'about_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isResetting = false;

  Future<void> _resetDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('初始化数据库'),
        content: const Text('此操作将删除本地数据库文件并重新创建，所有数据将丢失。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isResetting = true);

    try {
      await DatabaseHelper.instance.resetDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('数据库初始化成功，应用将重启...'),
            backgroundColor: Colors.green,
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Phoenix.rebirth(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isResetting = false);
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
        title: Text(
          '设置',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.accent),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionTitle('管理'),
          _buildTile(
            Icons.person_outline,
            '角色',
            '创建和管理角色设定',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RoleManagePage()),
            ),
          ),
          _buildTile(
            Icons.landscape_outlined,
            '场景',
            '创建和管理场景描述',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SceneManagePage()),
            ),
          ),
          _buildTile(
            Icons.public_outlined,
            '世界',
            '创建和管理世界设定',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorldManagePage()),
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('系统'),
          _buildTile(
            Icons.smart_toy_outlined,
            '智能体配置',
            '对话、压缩、记忆提取模型选择',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AgentConfigPage()),
            ),
          ),
          _buildTile(
            Icons.chat_outlined,
            '聊天设置',
            '深度思考、联网搜索、系统提示词',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatSettingsPage()),
            ),
          ),
          _buildTile(
            Icons.memory_outlined,
            '记忆压缩',
            '压缩参数、记忆提取参数、容量计算',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MemoryCompressionPage()),
            ),
          ),
          _buildTile(
            Icons.storage_outlined,
            '模型配置',
            'API Key、TTS、模型管理',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ModelConfigPage()),
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('自定义'),
          _buildTile(
            Icons.font_download_outlined,
            '字体',
            '切换全局字体样式和颜色',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FontConfigPage()),
            ),
          ),
          _buildTile(
            Icons.palette_outlined,
            '主题',
            '自定义头部、底部、背景颜色和图片',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ThemeConfigPage()),
            ),
          ),
          _buildTile(
            Icons.color_lens_outlined,
            '图标',
            '设置全局图标颜色',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IconConfigPage()),
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('语音'),
          _buildTile(
            Icons.record_voice_over_outlined,
            '音色',
            '为角色配置语音',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VoiceSettingsPage()),
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('应用'),
          _buildTile(
            Icons.info_outline,
            '我的应用',
            '开发者信息、版本号',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
          const SizedBox(height: 20),
          _buildTile(
            Icons.storage_outlined,
            '初始化数据库',
            '删除并重建本地数据库',
            _isResetting ? null : () => _resetDatabase(),
            color: Colors.red,
          ),
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

  Widget _buildTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap, {
    Color? color,
  }) {
    final effectiveColor = color ?? AppColors.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(
          icon,
          size: 22,
          color: color != null
              ? effectiveColor.withValues(alpha: 0.7)
              : AppColors.accent,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: effectiveColor,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.subText),
        ),
        trailing: Icon(
          Icons.chevron_right,
          size: 18,
          color: AppColors.subText.withValues(alpha: 0.4),
        ),
        onTap: onTap,
      ),
    );
  }
}
