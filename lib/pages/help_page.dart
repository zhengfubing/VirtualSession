import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_colors.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const _helpMd = '''
# 帮助

## 快速开始

进入 **设置 → 应用配置**，将阿里云百炼平台的 API Key 粘贴到输入框即可，所有密钥会自动同步。

百炼官网：https://bailian.console.aliyun.com/

登录方式：支付宝或阿里云 App 扫码登录，初次使用建议在控制台充值 10 元。

## 开发者选项

连续点击设置页面顶部的 **「设置」** 标题 **10 次**，即可开启开发者选项。
''';

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
          '帮助',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: Markdown(
        data: _helpMd,
        padding: const EdgeInsets.all(20),
        styleSheet: MarkdownStyleSheet(
          h1: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
          p: TextStyle(fontSize: 15, color: AppColors.subText, height: 1.7),
          strong: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
    );
  }
}
