import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'chat_list_page.dart';
import 'chat_page.dart';
import 'world_chat_page.dart';
import 'create_dialog_page.dart';
import 'solo_role_select_page.dart';
import 'main_page.dart';
import 'home_tab_page.dart';

class TabHomePage extends StatefulWidget {
  const TabHomePage({super.key});

  @override
  State<TabHomePage> createState() => _TabHomePageState();
}

class _TabHomePageState extends State<TabHomePage> {
  int _currentIndex = 0;
  final _homeKey = GlobalKey<HomeTabPageState>();
  final _soloKey = GlobalKey<ChatListPageState>();
  final _castKey = GlobalKey<ChatListPageState>();
  final _sagaKey = GlobalKey<ChatListPageState>();

  static const _tabs = [
    ('首页', Icons.home_outlined, Icons.home, _TabType.home),
    ('Solo', Icons.person_outline, Icons.person, _TabType.solo),
    ('Cast', Icons.group_outlined, Icons.group, _TabType.cast),
    ('Saga', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, _TabType.saga),
  ];

  _TabType get _currentType => _tabs[_currentIndex].$4;

  bool get _showAddButton => _currentType != _TabType.home;

  void _onChatSelected(String chatId, ChatFilter filter) {
    if (filter == ChatFilter.world) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WorldChatPage(initialChatId: chatId)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatPage(initialChatId: chatId)),
      );
    }
  }

  void _onCreateTap() {
    switch (_currentType) {
      case _TabType.solo:
        Navigator.of(context)
            .push(
              MaterialPageRoute(builder: (_) => const SoloRoleSelectPage()),
            )
            .then((_) => _soloKey.currentState?.refresh());
        break;
      case _TabType.cast:
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => CreateChatPage(
                  modeId: 'ensemble',
                  onCreated: (chatId) {
                    Navigator.of(context).pop();
                    _castKey.currentState?.refresh();
                    _onChatSelected(chatId, ChatFilter.ensemble);
                  },
                ),
              ),
            )
            .then((_) => _castKey.currentState?.refresh());
        break;
      case _TabType.saga:
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => CreateWorldPage(
                  onCreated: (chatId) {
                    Navigator.of(context).pop();
                    _sagaKey.currentState?.refresh();
                    _onChatSelected(chatId, ChatFilter.world);
                  },
                ),
              ),
            )
            .then((_) => _sagaKey.currentState?.refresh());
        break;
      case _TabType.home:
        break;
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
          _tabs[_currentIndex].$1,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_showAddButton)
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 26),
              color: AppColors.accent,
              onPressed: _onCreateTap,
              tooltip: '创建',
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeTabPage(key: _homeKey),
          ChatListPage(key: _soloKey, filter: ChatFilter.solo, onChatSelected: _onChatSelected),
          ChatListPage(key: _castKey, filter: ChatFilter.ensemble, onChatSelected: _onChatSelected),
          ChatListPage(key: _sagaKey, filter: ChatFilter.world, onChatSelected: _onChatSelected),
        ],
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: NavigationBarThemeData(
            height: 48,
            indicatorColor: Colors.transparent,
            backgroundColor: AppColors.appBarBg,
            surfaceTintColor: Colors.transparent,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return TextStyle(fontSize: 10, color: AppColors.accent);
              }
              return TextStyle(fontSize: 10, color: AppColors.subText);
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return IconThemeData(size: 20, color: AppColors.accent);
              }
              return IconThemeData(size: 20, color: AppColors.subText);
            }),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: _tabs.map((t) {
            return NavigationDestination(
              icon: Icon(t.$2, color: AppColors.subText),
              selectedIcon: Icon(t.$3, color: AppColors.accent),
              label: t.$1,
            );
          }).toList(),
        ),
      ),
    );
  }
}

enum _TabType { home, solo, cast, saga }
