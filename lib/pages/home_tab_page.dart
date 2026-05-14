import 'package:flutter/material.dart';
import '../services/home_data_service.dart';
import '../theme/app_colors.dart';

class HomeTabPage extends StatefulWidget {
  const HomeTabPage({super.key});

  @override
  State<HomeTabPage> createState() => HomeTabPageState();
}

class HomeTabPageState extends State<HomeTabPage>
    with SingleTickerProviderStateMixin {
  HomeData? _data;
  bool _isLoading = true;
  late AnimationController _staggerController;
  late List<Animation<double>> _itemAnims;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _loadData();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final data = await HomeData.load();
    if (mounted) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
      _itemAnims = List.generate(4, (i) {
        return CurvedAnimation(
          parent: _staggerController,
          curve: Interval(i * 0.2, 1.0 - (3 - i) * 0.1,
              curve: Curves.easeOut),
        );
      });
      _staggerController.forward();
    }
  }

  Future<void> refresh() async {
    HomeData.clear();
    setState(() => _isLoading = true);
    _staggerController.reset();
    await _loadData();
  }

  String _formatTokens(int tokens) {
    if (tokens <= 0) return '0';
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K';
    return tokens.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _data == null) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: AppColors.subText.withValues(alpha: 0.5),
            strokeWidth: 2,
          ),
        ),
      );
    }

    final d = _data!;
    final anims = _itemAnims;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        _fadeIn(0, anims, _buildTokenSection(d)),
        const SizedBox(height: 24),
        _fadeIn(1, anims, _buildModeSection(d)),
        const SizedBox(height: 24),
        _fadeIn(2, anims, _buildCountSection(d)),
        const SizedBox(height: 32),
        _fadeIn(3, anims, _buildFooter()),
      ],
    );
  }

  Widget _fadeIn(int index, List<Animation<double>> anims, Widget child) {
    if (index >= anims.length) return child;
    return AnimatedBuilder(
      animation: anims[index],
      builder: (context, _) {
        return Opacity(
          opacity: anims[index].value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - anims[index].value) * 12),
            child: child,
          ),
        );
      },
    );
  }

  // ==================== Token Section ====================

  Widget _buildTokenSection(HomeData d) {
    final total = d.totalTokens;
    final promptPct = total > 0 ? d.totalPromptTokens / total : 0.0;
    final completionPct = total > 0 ? d.totalCompletionTokens / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Token 用量',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.subText,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatTokens(total),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'tokens',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.subText,
                ),
              ),
            ),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Row(
                children: [
                  Flexible(
                    flex: (promptPct * 100).round().clamp(1, 100),
                    child: Container(color: AppColors.accent),
                  ),
                  Flexible(
                    flex: (completionPct * 100).round().clamp(1, 100),
                    child: Container(
                      color: AppColors.accent.withValues(alpha: 0.25),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legendDot(AppColors.accent),
              const SizedBox(width: 5),
              Text(
                '输入 ${_formatTokens(d.totalPromptTokens)}',
                style: TextStyle(fontSize: 12, color: AppColors.subText),
              ),
              const SizedBox(width: 14),
              _legendDot(AppColors.accent.withValues(alpha: 0.25)),
              const SizedBox(width: 5),
              Text(
                '输出 ${_formatTokens(d.totalCompletionTokens)}',
                style: TextStyle(fontSize: 12, color: AppColors.subText),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1),
        color: color,
      ),
    );
  }

  // ==================== Mode Section ====================

  Widget _buildModeSection(HomeData d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '对话模式',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.subText,
          ),
        ),
        const SizedBox(height: 10),
        _buildModeRow(
          label: 'Solo',
          desc: '单角色一对一',
          count: d.soloCount,
        ),
        _buildDivider(),
        _buildModeRow(
          label: 'Cast',
          desc: '多角色群像',
          count: d.castCount,
        ),
        _buildDivider(),
        _buildModeRow(
          label: 'Saga',
          desc: '世界冒险',
          count: d.sagaCount,
        ),
      ],
    );
  }

  Widget _buildModeRow({
    required String label,
    required String desc,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: TextStyle(fontSize: 13, color: AppColors.subText),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: AppColors.subText.withValues(alpha: 0.15),
    );
  }

  // ==================== Count Section ====================

  Widget _buildCountSection(HomeData d) {
    return Row(
      children: [
        _buildCountItem('角色', d.roleCount),
        Container(
          width: 0.5,
          height: 32,
          color: AppColors.subText.withValues(alpha: 0.15),
        ),
        _buildCountItem('场景', d.sceneCount),
        Container(
          width: 0.5,
          height: 32,
          color: AppColors.subText.withValues(alpha: 0.15),
        ),
        _buildCountItem('世界', d.worldCount),
      ],
    );
  }

  Widget _buildCountItem(String label, int count) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.subText),
          ),
        ],
      ),
    );
  }

  // ==================== Footer ====================

  Widget _buildFooter() {
    return Center(
      child: Text(
        'ZFB · 数据存储在本地，对话经由 AI 服务商处理',
        style: TextStyle(
          fontSize: 11,
          color: AppColors.subText.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
