import 'package:flutter/material.dart';
import '../models/solo_memory.dart';
import '../services/solo_memory_service.dart';
import '../utils/time_format.dart';
import '../theme/app_colors.dart';
import 'solo_memory_edit_page.dart';

class SoloMemoryListPage extends StatefulWidget {
  final String sessionId;
  final String sessionName;

  const SoloMemoryListPage({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  @override
  State<SoloMemoryListPage> createState() => _SoloMemoryListPageState();
}

class _SoloMemoryListPageState extends State<SoloMemoryListPage> {
  final _memoryService = SoloMemoryService.instance;
  List<SoloMemory> _memories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() => _isLoading = true);
    final rows = await _memoryService.listMemories(widget.sessionId);
    final memories = rows.map((r) => SoloMemory.fromMap(r)).toList();
    if (mounted) {
      setState(() {
        _memories = memories;
        _isLoading = false;
      });
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
          '${widget.sessionName} 的记忆',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _memories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.memory_outlined, size: 48, color: AppColors.subText),
                      const SizedBox(height: 12),
                      Text(
                        '暂无记忆',
                        style: TextStyle(color: AppColors.subText, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '对话足够多后，系统会自动提取记忆',
                        style: TextStyle(color: AppColors.subText.withValues(alpha: 0.6), fontSize: 12),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMemories,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _memories.length,
                    itemBuilder: (ctx, i) => _buildMemoryCard(_memories[i]),
                  ),
                ),
    );
  }

  Widget _buildMemoryCard(SoloMemory memory) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SoloMemoryEditPage(memoryId: memory.id),
            ),
          );
          _loadMemories();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C4DFF)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      memory.brief,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (memory.tags.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: memory.tags.map((tag) => _buildTag(tag)).toList(),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Icon(Icons.access_time, size: 13, color: AppColors.subText),
                  const SizedBox(width: 4),
                  Text(
                    '${TimeFormat.chatTime(memory.timeRangeStart)} ~ ${TimeFormat.chatTime(memory.timeRangeEnd)}',
                    style: TextStyle(fontSize: 11, color: AppColors.subText.withValues(alpha: 0.7)),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.subText.withValues(alpha: 0.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String tag) {
    final cs = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    switch (tag) {
      case 'cross_day':
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFE65100);
        break;
      case 'important_event':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        break;
      case 'important_result':
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1565C0);
        break;
      case 'large_time_gap':
        bg = const Color(0xFFFCE4EC);
        fg = const Color(0xFFC62828);
        break;
      default:
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _tagLabel(tag),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }

  String _tagLabel(String tag) {
    switch (tag) {
      case 'cross_day':
        return '跨天';
      case 'important_event':
        return '重要事件';
      case 'important_result':
        return '重要结果';
      case 'large_time_gap':
        return '大间隔';
      default:
        return tag;
    }
  }
}
