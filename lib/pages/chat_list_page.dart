import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../services/file_storage_service.dart';
import '../theme/app_colors.dart';
import 'solo_chat_page.dart';

enum ChatFilter { solo, ensemble, world }

class _ChatItem {
  final String id;
  final String name;
  final ChatFilter filter;
  final double createdAt;
  final double updatedAt;
  final String? senderId;
  final String? avatarPath;
  final int totalTokens;
  final List<String> roleNames;
  final Map<String, String?> roleAvatarPaths;
  final String roleName;

  _ChatItem({
    required this.id,
    required this.name,
    required this.filter,
    required this.createdAt,
    required this.updatedAt,
    this.senderId,
    this.avatarPath,
    this.totalTokens = 0,
    this.roleNames = const [],
    this.roleAvatarPaths = const {},
    this.roleName = '',
  });
}

class ChatListPage extends StatefulWidget {
  final ChatFilter filter;
  final void Function(String chatId, ChatFilter filter)? onChatSelected;

  const ChatListPage({
    super.key,
    required this.filter,
    this.onChatSelected,
  });

  @override
  State<ChatListPage> createState() => ChatListPageState();
}

class ChatListPageState extends State<ChatListPage> {
  final _db = DatabaseHelper.instance;
  final _fileStorage = FileStorageService();
  List<_ChatItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> refresh() => _loadData();

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final items = <_ChatItem>[];
    final tokenTotals = await _db.query('token_usage_totals');
    final tokenMap = <String, int>{};
    for (final row in tokenTotals) {
      final chatId = row['chat_id'] as String;
      final prompt = row['prompt_tokens'] as int? ?? 0;
      final completion = row['completion_tokens'] as int? ?? 0;
      tokenMap[chatId] = (tokenMap[chatId] ?? 0) + prompt + completion;
    }

    if (widget.filter == ChatFilter.solo) {
      // Solo: from solo_sessions + chats with mode_id = 'solo'
      final soloSessions = await _db.query(
        'solo_sessions',
        where: 'deleted_at IS NULL',
        orderBy: 'updated_at DESC',
      );
      for (final s in soloSessions) {
        final aiRoleName = s['ai_role_name'] as String? ?? '';
        final userRoleName = s['user_role_name'] as String? ?? '';
        String? avatarPath;
        if (aiRoleName.isNotEmpty) {
          avatarPath = await _fileStorage.getRoleAvatarPath(aiRoleName);
        }
        items.add(_ChatItem(
          id: s['id'] as String,
          name: aiRoleName,
          filter: ChatFilter.solo,
          createdAt: (s['created_at'] as num).toDouble(),
          updatedAt: (s['updated_at'] as num).toDouble(),
          senderId: userRoleName,
          avatarPath: avatarPath,
          totalTokens: tokenMap[s['id'] as String] ?? 0,
          roleName: aiRoleName,
        ));
      }
      // Also load chats with mode_id = 'solo'
      final soloChats = await _db.query(
        'chats',
        where: 'deleted_at IS NULL AND mode_id = ?',
        whereArgs: ['solo'],
        orderBy: 'updated_at DESC',
      );
      for (final c in soloChats) {
        final senderId = c['sender_id'] as String? ?? 'empty';
        String? avatarPath;
        if (senderId != 'empty' && senderId.isNotEmpty) {
          avatarPath = await _fileStorage.getRoleAvatarPath(senderId);
        }
        final roleName = c['role_name'] as String? ?? '';
        items.add(_ChatItem(
          id: c['id'] as String,
          name: roleName.isNotEmpty ? roleName : (c['name'] as String? ?? ''),
          filter: ChatFilter.solo,
          createdAt: (c['created_at'] as num).toDouble(),
          updatedAt: (c['updated_at'] as num).toDouble(),
          senderId: senderId,
          avatarPath: avatarPath,
          totalTokens: tokenMap[c['id'] as String] ?? 0,
          roleName: roleName,
        ));
      }
    } else if (widget.filter == ChatFilter.ensemble) {
      // Ensemble: chats with mode_id = 'ensemble' (or not 'solo')
      final chats = await _db.query(
        'chats',
        where: 'deleted_at IS NULL AND (mode_id IS NULL OR mode_id != ?)',
        whereArgs: ['solo'],
        orderBy: 'updated_at DESC',
      );
      for (final c in chats) {
        final senderId = c['sender_id'] as String? ?? 'empty';
        String? avatarPath;
        if (senderId != 'empty' && senderId.isNotEmpty) {
          avatarPath = await _fileStorage.getRoleAvatarPath(senderId);
        }
        final rolesJson = c['role_setting_prompt_ids_json'] as String? ?? '[]';
        List<String> roleNames = [];
        try {
          final decoded = jsonDecode(rolesJson);
          if (decoded is List) {
            roleNames = decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {}
        final avatarPaths = <String, String?>{};
        for (final rn in roleNames) {
          avatarPaths[rn] = await _fileStorage.getRoleAvatarPath(rn);
        }
        items.add(_ChatItem(
          id: c['id'] as String,
          name: c['name'] as String? ?? '',
          filter: ChatFilter.ensemble,
          createdAt: (c['created_at'] as num).toDouble(),
          updatedAt: (c['updated_at'] as num).toDouble(),
          senderId: senderId,
          avatarPath: avatarPath,
          totalTokens: tokenMap[c['id'] as String] ?? 0,
          roleNames: roleNames,
          roleAvatarPaths: avatarPaths,
        ));
      }
    } else if (widget.filter == ChatFilter.world) {
      // World: world_chats
      final worldChats = await _db.query(
        'world_chats',
        where: 'deleted_at IS NULL',
        orderBy: 'updated_at DESC',
      );
      for (final w in worldChats) {
        final worldRoles = await _db.query(
          'world_chat_roles',
          where: 'world_chat_id = ?',
          whereArgs: [w['id'] as String],
        );
        final roleNames = worldRoles
            .map((r) => r['role_name'] as String)
            .toList();
        final avatarPaths = <String, String?>{};
        for (final rn in roleNames) {
          avatarPaths[rn] = await _fileStorage.getRoleAvatarPath(rn);
        }
        items.add(_ChatItem(
          id: w['id'] as String,
          name: w['name'] as String? ?? '',
          filter: ChatFilter.world,
          createdAt: (w['created_at'] as num).toDouble(),
          updatedAt: (w['updated_at'] as num).toDouble(),
          totalTokens: tokenMap[w['id'] as String] ?? 0,
          roleNames: roleNames,
          roleAvatarPaths: avatarPaths,
        ));
      }
    }

    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  String _formatTime(double timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatTokens(int tokens) {
    if (tokens <= 0) return '0';
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K';
    return '$tokens';
  }

  Future<void> _deleteItem(_ChatItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('确认删除'),
        content: Text('确定要删除「${item.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final table = item.filter == ChatFilter.world
        ? 'world_chats'
        : item.filter == ChatFilter.solo
            ? 'solo_sessions'
            : 'chats';
    await _db.update(
      table,
      {'deleted_at': DateTime.now().millisecondsSinceEpoch / 1000},
      where: 'id = ?',
      whereArgs: [item.id],
    );
    _loadData();
  }

  Widget _buildAvatar(_ChatItem item) {
    if (item.filter == ChatFilter.world) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.worldBg,
        child: const Icon(
          Icons.auto_awesome_rounded,
          size: 18,
          color: AppColors.world,
        ),
      );
    }

    if (item.avatarPath != null && item.avatarPath!.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: FileImage(File(item.avatarPath!)),
      );
    }

    return CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.accent.withValues(alpha: 0.1),
      child: Text(
        _getInitial(item),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
        ),
      ),
    );
  }

  String _getInitial(_ChatItem item) {
    if (item.senderId != null &&
        item.senderId!.isNotEmpty &&
        item.senderId != 'empty') {
      return item.senderId![0].toUpperCase();
    }
    if (item.name.isNotEmpty) return item.name[0].toUpperCase();
    return 'C';
  }

  Widget _buildRoleAvatars(_ChatItem item) {
    const maxShow = 4;
    final names = item.roleNames;
    final showNames = names.take(maxShow).toList();
    final remaining = names.length - maxShow;

    return Row(
      children: [
        ...showNames.map((name) {
          final avatarPath = item.roleAvatarPaths[name];
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: CircleAvatar(
              radius: 9,
              backgroundColor: AppColors.accent.withValues(alpha: 0.1),
              backgroundImage: avatarPath != null
                  ? FileImage(File(avatarPath))
                  : null,
              child: avatarPath == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    )
                  : null,
            ),
          );
        }),
        if (remaining > 0)
          CircleAvatar(
            radius: 9,
            backgroundColor: AppColors.accent.withValues(alpha: 0.1),
            child: Text(
              '+$remaining',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChatCard(_ChatItem item) {
    final timeStr = _formatTime(item.updatedAt);

    return InkWell(
      onTap: () {
        if (item.filter == ChatFilter.solo) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SoloChatPage(
                aiRoleName: item.roleName.isNotEmpty ? item.roleName : item.name,
                userRoleName: item.senderId ?? 'empty',
              ),
            ),
          );
        } else {
          widget.onChatSelected?.call(item.id, item.filter);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildAvatar(item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (item.filter == ChatFilter.solo && item.senderId != null && item.senderId != 'empty') ...[
                    const SizedBox(height: 2),
                    Text(
                      '扮演: ${item.senderId}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.subText.withValues(alpha: 0.7),
                      ),
                    ),
                  ] else if (item.roleNames.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildRoleAvatars(item),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: AppColors.subText.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.subText.withValues(alpha: 0.7),
                        ),
                      ),
                      if (item.totalTokens > 0) ...[
                        const SizedBox(width: 10),
                        Icon(
                          Icons.token_rounded,
                          size: 12,
                          color: AppColors.subText.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _formatTokens(item.totalTokens),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.subText.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.subText.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2,
        ),
      );
    }

    if (_items.isEmpty) {
      final label = widget.filter == ChatFilter.solo
          ? 'Solo'
          : widget.filter == ChatFilter.ensemble
              ? 'Cast'
              : 'Saga';
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: AppColors.subText.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有 $label 会话',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.subText,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '点右上角 + 开始一段对话吧',
              style: TextStyle(fontSize: 13, color: AppColors.subText),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          final isLast = index == _items.length - 1;
          return Dismissible(
            key: Key(item.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.redAccent,
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              await _deleteItem(item);
              return false;
            },
            child: Column(
              children: [
                _buildChatCard(item),
                if (!isLast)
                  Divider(
                    height: 1,
                    indent: 60,
                    color: AppColors.subText.withValues(alpha: 0.1),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
