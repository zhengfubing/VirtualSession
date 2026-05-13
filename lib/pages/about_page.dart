import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

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
          '我的应用',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.android_rounded,
                size: 44,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'ZfbAI',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'v0.1.0-beta',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          _buildInfoCard([
            _buildInfoRow(Icons.person_outline, '开发者', 'zfb'),
            Divider(height: 1, indent: 44, color: AppColors.divider),
            _buildInfoRow(Icons.email_outlined, '联系邮箱', '2897027297@qq.com'),
            Divider(height: 1, indent: 44, color: AppColors.divider),
            _buildInfoRow(Icons.update_outlined, '最新版本更新时间', '2026-05-11'),
            Divider(height: 1, indent: 44, color: AppColors.divider),
            _buildInfoRow(Icons.science_outlined, '版本类型', '测试版本'),
          ]),
          const SizedBox(height: 20),
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
                      '关于此版本',
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
                  '当前为测试版本，功能和界面可能随版本更新发生变化。如有问题或建议，请通过邮箱联系开发者。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.subText,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                      Icons.shield_outlined,
                      size: 16,
                      color: AppColors.subText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '数据与隐私',
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
                  '本应用所有数据均保存在本地设备，不依赖任何后台服务器。'
                  '仅 AI 对话生成内容时，会将消息发送至对应的 AI 服务商进行处理。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.subText,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 14, color: AppColors.text)),
          const Spacer(),
          SelectableText(
            value,
            style: TextStyle(fontSize: 14, color: AppColors.subText),
          ),
        ],
      ),
    );
  }
}
