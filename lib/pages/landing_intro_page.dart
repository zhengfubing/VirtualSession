import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'about_page.dart';

class LandingIntroPage extends StatelessWidget {
  const LandingIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildHeader(),
            const SizedBox(height: 32),
            _buildSectionTitle('核心功能'),
            const SizedBox(height: 12),
            _buildFeatureCard(
              icon: Icons.chat_bubble_outline_rounded,
              color: AppColors.accent,
              title: 'AI 角色对话',
              desc: '创建多个角色会话，与不同性格、背景的 AI 角色进行沉浸式对话。支持多角色切换和场景切换。',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              icon: Icons.public_outlined,
              color: AppColors.world,
              title: '世界聊天',
              desc: '构建完整的世界观设定，在自定义世界中展开多角色互动叙事，体验更丰富的剧情玩法。',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              icon: Icons.record_voice_over_outlined,
              color: AppColors.accent,
              title: '语音合成',
              desc: '支持为角色配置专属音色，AI 回复可自动朗读，带来更生动的交互体验。',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              icon: Icons.wifi_tethering_outlined,
              color: AppColors.accent,
              title: '联网搜索',
              desc: 'AI 可自动联网搜索实时信息，随时获取最新资讯。',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              icon: Icons.compress_outlined,
              color: AppColors.accent,
              title: '智能上下文压缩',
              desc: '对话过长时自动进行摘要压缩，在节省 Token 的同时保留关键信息和角色状态。',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              icon: Icons.palette_outlined,
              color: AppColors.accent,
              title: '个性化定制',
              desc: '自定义主题颜色、背景图片、全局字体，打造属于你的专属聊天界面。',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              icon: Icons.storage_outlined,
              color: AppColors.accent,
              title: '本地数据存储',
              desc: '所有数据均保存在本地设备，不依赖后台服务器。仅 AI 对话时将消息发送至对应 AI 服务商处理。',
            ),
            const SizedBox(height: 28),
            _buildSectionTitle('了解更多'),
            const SizedBox(height: 12),
            _buildInfoLink(
              context,
              icon: Icons.info_outline,
              title: '我的应用',
              subtitle: '版本信息、开发者、数据与隐私',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
            const SizedBox(height: 28),
            _buildFooter(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.android_rounded,
            size: 30,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'ZfbAI',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '一款本地化 AI 角色对话应用，支持多角色会话、世界聊天、语音合成与个性化定制。',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.subText,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
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

  Widget _buildInfoLink(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.subText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.subText.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Column(
        children: [
          Text(
            'ZfbAI',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.subText.withValues(alpha: 0.6),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'v0.1.0-beta',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.subText.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
