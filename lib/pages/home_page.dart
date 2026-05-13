import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'all_chats_page.dart';
import 'chat_page.dart';
import 'create_dialog_page.dart';
import 'world_chat_page.dart';
import 'solo_role_select_page.dart';
import 'main_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _homeKey = GlobalKey<AllChatsPageState>();

  void _onChatSelected(String chatId, ChatItemType type) {
    if (type == ChatItemType.chat) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatPage(initialChatId: chatId)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WorldChatPage(initialChatId: chatId)),
      );
    }
  }

  void _showCreateMenu() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMenuOption(
              icon: Icons.person_outline,
              iconColor: AppColors.accent,
              label: '独幕',
              subtitle: '单场景单角色，深度一对一沉浸',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SoloRoleSelectPage()),
                );
              },
            ),
            Divider(
              height: 1,
              indent: 56,
              color: AppColors.subText.withValues(alpha: 0.08),
            ),
            _buildMenuOption(
              icon: Icons.group_outlined,
              iconColor: AppColors.accent,
              label: '群像',
              subtitle: '单场景多角色，群像剧式互动',
              onTap: () {
                Navigator.pop(ctx);
                _navigateToCreateChat('ensemble');
              },
            ),
            Divider(
              height: 1,
              indent: 56,
              color: AppColors.subText.withValues(alpha: 0.08),
            ),
            _buildMenuOption(
              icon: Icons.auto_awesome_outlined,
              iconColor: AppColors.world,
              label: 'Saga',
              subtitle: '多场景多角色，宏大叙事世界',
              onTap: () {
                Navigator.pop(ctx);
                _navigateToCreate(ChatItemType.world);
              },
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.subText.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToCreateChat(String modeId) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CreateChatPage(
              modeId: modeId,
              onCreated: (chatId) {
                Navigator.of(context).pop();
                _homeKey.currentState?.refresh();
                _onChatSelected(chatId, ChatItemType.chat);
              },
            ),
          ),
        )
        .then((_) => _homeKey.currentState?.refresh());
  }

  void _navigateToCreate(ChatItemType type) {
    if (type == ChatItemType.chat) {
      _navigateToCreateChat('ensemble');
    } else {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => CreateWorldPage(
                onCreated: (chatId) {
                  Navigator.of(context).pop();
                  _homeKey.currentState?.refresh();
                  _onChatSelected(chatId, ChatItemType.world);
                },
              ),
            ),
          )
          .then((_) => _homeKey.currentState?.refresh());
    }
  }

  String get _currentTitle => '会话';

  Widget _buildBody() {
    return AllChatsPage(key: _homeKey, onChatSelected: _onChatSelected);
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: AppColors.appBarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined, size: 22),
          color: AppColors.accent,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MainPage()),
          ),
          tooltip: '设置',
        ),
        title: Text(
          _currentTitle,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 26),
            color: AppColors.accent,
            onPressed: _showCreateMenu,
            tooltip: '创建',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
