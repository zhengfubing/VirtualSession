# Solo 模式重构实现计划

## 目标

1. Solo 模式改为**基于 AI 角色**：一个 AI 角色只有一个持久会话（而非可创建多个 chat）
2. 消息增加**时间字段**展示，压缩逻辑基于时间考量
3. Solo 模式的数据库表、服务层、UI 层**完全独立**于 Ensemble/Saga

---

## 一、数据库迁移（database_helper.dart → version 10）

### 1.1 新增 `solo_sessions` 表

```sql
CREATE TABLE solo_sessions (
  id TEXT PRIMARY KEY,               -- = ai_role_name（如 "Cheryl"），无扩展名
  ai_role_name TEXT NOT NULL UNIQUE,  -- AI 角色名（如 "Cheryl"）
  user_role_name TEXT NOT NULL,       -- 用户扮演的角色名
  scene_prompt_id TEXT NOT NULL DEFAULT 'empty',
  status TEXT NOT NULL DEFAULT 'active',
  system_prompt_json TEXT NOT NULL DEFAULT '{}',  -- 预构建的 system prompt 快照
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL,
  deleted_at REAL
);
```

### 1.2 数据迁移：现有 Solo chat → solo_sessions

迁移逻辑（在 `_onUpgrade` version 10 中执行）：

```dart
// 1. 保留原 chats 表中 mode_id='solo' 的记录（不删除），但标记迁移状态
// 2. 从 chats 表提取 solo 数据插入 solo_sessions
//    - id = role_name（去掉 .md 后缀）
//    - ai_role_name = role_name
//    - user_role_name = sender_id（Solo 模式下 sender_id 即用户角色）
//    - scene_prompt_id = scene_prompt_id
//    - created_at / updated_at 沿用
//    - 如果同一个 ai_role_name 有多条 chat，取最新那条
```

关键点：
- `messages` / `context_items` / `summaries` 三张表的 `chat_id` 字段指向 `solo_sessions.id`
- 迁移时需更新这些表的历史数据的 `chat_id`
- 旧 `chats` 表中的 Solo 记录**不删除**，保留做历史参照

### 1.3 消息表时间字段确认

`messages` 和 `context_items` 表已有 `created_at` 字段（REAL 类型，Unix 秒级时间戳），**无需修改**。只需在读取时转换为 `DateTime` 并在 UI 展示。

---

## 二、数据模型

### 2.1 DisplayMessage 增加时间字段

文件：`lib/pages/chat_page.dart`（保留共用部分）

```dart
class DisplayMessage {
  final String id;
  final DisplayMessageType type;
  String senderName;
  String content;
  final String scene;
  final List<String> status;
  final String statusType;
  final String statusContent;
  bool isStreaming;
  bool isExpanded;
  final DateTime createdAt;  // 新增

  DisplayMessage({
    required this.id,
    required this.type,
    this.senderName = '',
    required this.content,
    this.scene = '',
    this.status = const [],
    this.statusType = '',
    this.statusContent = '',
    this.isStreaming = false,
    this.isExpanded = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
```

---

## 三、新建文件清单

### 3.1 `lib/services/solo_session_service.dart`

Solo 模式专属的会话管理服务。用 `ai_role_name` 作为 session 的唯一标识。

```dart
class SoloSessionService {
  static final SoloSessionService instance = SoloSessionService._();

  /// 根据 AI 角色名获取或创建会话
  /// 如果该角色已有会话则返回已有，否则创建新会话
  Future<Map<String, dynamic>> getOrCreateSession({
    required String aiRoleName,
    required String userRoleName,
    String scenePromptId = 'empty',
  });

  /// 获取某个 AI 角色的会话（不存在返回 null）
  Future<Map<String, dynamic>?> getSession(String aiRoleName);

  /// 获取所有活跃 Solo 会话列表
  Future<List<Map<String, dynamic>>> listSessions();

  /// 更新会话设置（场景、用户角色）
  Future<void> updateSession({
    required String sessionId,
    String? scenePromptId,
    String? userRoleName,
  });

  /// 软删除会话（清空历史）
  Future<void> deleteSession(String sessionId);

  /// 获取完整的 chat state（复用 ChatStateService 的查询逻辑，但针对 solo_sessions.id）
  Future<Map<String, dynamic>> getChatState(String sessionId);

  /// 确保 chat state 存在
  Future<Map<String, dynamic>> ensureChatState(String sessionId);
}
```

**关键实现细节**：
- `getOrCreateSession` 中 `id = aiRoleName.replaceAll('.md', '')`
- 内部调用 `ChatStateService` 的 `getChatState`/`ensureChatState`，传入 `solo_session.id` 作为 `chatId`
- `addMessage` / `addContextItem` 直接复用 `ChatStateService.instance` 的对应方法
- 不需要新建独立的消息表

### 3.2 `lib/pages/solo_role_select_page.dart`

选择 AI 角色的页面。替代 Solo 模式下的 `CreateChatPage`。

**UI 布局**：
- AppBar 标题：`独幕`
- 列表展示所有角色（从 `FileStorageService.getAllRoles()` 获取）
- 每个角色项显示：头像、角色名
- 点击角色 → 如果已有 session 则直接进入，否则弹出 quick setup 弹窗

**Quick Setup 弹窗**（首次选择角色时）：
- 选择"我扮演的角色"（下拉或 chips）
- 选择场景（可选）
- 确认后创建 `solo_session` 并进入 `SoloChatPage`

### 3.3 `lib/pages/solo_chat_page.dart`

Solo 专用的聊天页面，**独立于 `ChatPage`**。

与 `ChatPage` 的关键差异：

| 特性 | ChatPage (Ensemble/Saga) | SoloChatPage |
|------|--------------------------|--------------|
| 会话 ID | UUID chat_id | ai_role_name |
| 创建流程 | CreateChatPage → UUID | 选角色直接进入 |
| 角色/场景设置 | 弹窗切换 | 固定不变，顶部展示 AI 角色名 |
| 发送者显示 | 可选发送者下拉 | 固定为 user_role_name |
| 时间展示 | 无 | 每条消息右侧/底部显示时间 |
| SystemPrompt | 动态构建 | 创建时构建并缓存到 `solo_sessions.system_prompt_json` |
| 消息气泡 | 用户右对齐、AI 左对齐 | 用户右对齐、AI 左对齐（同现有 Solo 样式） |

**消息时间显示规则**：
- 同一天的消息：显示 `HH:mm`
- 跨天的消息：显示 `MM-dd HH:mm`
- 如果与前一条消息间隔 > 30 分钟，显示时间分隔线

**`SoloChatPage` 需要接收的参数**：
```dart
class SoloChatPage extends StatefulWidget {
  final String aiRoleName;   // AI 角色名（同时也是 session_id）
  final String userRoleName; // 用户扮演角色名
  final String? scenePromptId;
}
```

### 3.4 `lib/services/solo_context_builder.dart`（可选，后续需要时创建）

为后续的记忆功能预留。当前阶段直接用 `ContextBuilderService.buildEffectiveContext`。

---

## 四、修改现有文件

### 4.1 `lib/pages/home_page.dart`

修改 `_showCreateMenu()` 中"独幕"按钮的行为：

```dart
// 旧：跳转到 CreateChatPage(modeId: 'solo')
// 新：跳转到 SoloRoleSelectPage
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
```

### 4.2 `lib/pages/all_chats_page.dart`

Solo 会话**不再出现在会话列表中**（Solo 有自己独立的入口）。修改 `_loadData()`：

```dart
// 旧：查询 chats 表，mode_id='solo' 的也展示
// 新：只查询 mode_id != 'solo' 的 chats
final chats = await _db.query(
  'chats',
  where: 'deleted_at IS NULL AND mode_id != ?',
  whereArgs: ['solo'],
  orderBy: 'updated_at DESC',
);
```

或者如果想让 Solo 会话也出现在列表中（方便用户直接进入），则改为从 `solo_sessions` 表加载并用 `ChatItemType.chat` 展示，点击后跳转 `SoloChatPage`。**建议采用此方案**，用户体验更好——不用每次都从角色列表进入。

### 4.3 `lib/database/database_helper.dart`

在 `_onUpgrade` 中增加 version 10 的迁移逻辑：

```dart
if (oldVersion < 10) {
  // 1. 创建 solo_sessions 表
  await db.execute('''...''');
  // 2. 迁移现有 Solo chats 到 solo_sessions
  await _migrateSoloChats(db);
  // 3. 更新 messages / context_items / summaries 的 chat_id
  await _migrateSoloReferences(db);
}
```

### 4.4 `lib/models/chat_mode.dart`（或数据库中的 chat_modes 表）

更新 Solo 模式的记录：

```sql
UPDATE chat_modes 
SET memory_enabled = 1, memory_type = 'time_aware'
WHERE id = 'solo';
```

---

## 五、时间机制详细设计

### 5.1 UI 层面

消息气泡右下角显示发送时间：

```
┌──────────────────────────────────┐
│ 你好，今天天气真不错呢            │
│                         14:30    │
└──────────────────────────────────┘
```

时间格式化函数（放入 `lib/utils/time_format.dart`）：

```dart
class TimeFormat {
  /// 聊天消息时间格式
  static String chatTime(DateTime dt, {DateTime? previousDt}) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    
    if (isToday) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    
    final isThisYear = dt.year == now.year;
    if (isThisYear) {
      return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
  
  /// 是否需要显示时间分隔线（与前一条消息间隔超过 30 分钟）
  static bool shouldShowTimeGap(DateTime current, DateTime? previous) {
    if (previous == null) return false;
    return current.difference(previous).inMinutes > 30;
  }
}
```

### 5.2 压缩层面

在 `CompressionService._buildSnapshot` 中增加时间感知（对 Solo 模式特化，但不破坏现有逻辑）：

核心改动：在选择可压缩消息时，考虑时间间隔。如果两条相邻消息间隔 > N 小时，优先将它们分在不同的压缩批次中。这个逻辑可以在 Solo 的记忆提取层实现，**不修改共享的 CompressionService**，而是在新的 `SoloMemoryService` 中处理。

---

## 六、与记忆功能的关系

本次重构是记忆功能的**前置基础设施**：

| 本次完成 | 后续记忆功能用到的 |
|----------|-------------------|
| `solo_sessions` 表 | 记忆表的 `session_id` 外键 |
| 消息时间展示 + 时间戳 | 记忆提取时自动判断跨天/跨会话 |
| AI 角色 = 唯一会话 | 记忆自然累积，无需跨 chat 合并 |
| `system_prompt_json` 缓存 | 记忆注入 system prompt 时有固定锚点 |
| `SoloSessionService` | 后续 `SoloMemoryService` 的调用入口 |
| `solo_chat_page.dart` | 后续记忆 UI（记忆时间线、摘要展示）的宿主页面 |

---

## 七、实施顺序

| 步骤 | 内容 | 涉及文件 |
|------|------|----------|
| 1 | 数据库迁移 v10：创建 `solo_sessions` 表 + 迁移旧数据 | `database_helper.dart` |
| 2 | 新建 `SoloSessionService` | `services/solo_session_service.dart` |
| 3 | 新建 `TimeFormat` 工具类 | `utils/time_format.dart` |
| 4 | 修改 `DisplayMessage` 增加 `createdAt` | `pages/chat_page.dart` |
| 5 | 新建 `SoloRoleSelectPage` | `pages/solo_role_select_page.dart` |
| 6 | 新建 `SoloChatPage`（含时间展示） | `pages/solo_chat_page.dart` |
| 7 | 修改 `home_page.dart` 独幕入口指向新页面 | `pages/home_page.dart` |
| 8 | 修改 `all_chats_page.dart` 集成 Solo 会话列表 | `pages/all_chats_page.dart` |
| 9 | 更新 `chat_modes` 表 Solo 的 memory 标志 | `database_helper.dart` |

---

## 八、注意事项

1. **不删除旧 chats 表中的 Solo 记录**，迁移后在 `all_chats_page` 中过滤 `mode_id != 'solo'`
2. **`messages` / `context_items` / `summaries` 三表结构不变**，Solo 复用它们，`chat_id` 指向 `solo_sessions.id`
3. **共享服务不动**：`AIService`, `CompressionService`, `ContextBuilderService`, `DialogParserService`, `PromptBuilderService` 等保持不变
4. **现有的 `ChatPage` 中 Solo 相关分支代码**（`if (_currentModeId == 'solo')`）可以保留不动，或者逐步清理。优先保证新页面功能完整后再清理旧代码
5. **`CreateChatPage` 的 Solo 模式分支**（`_isSolo`）保留不动，但入口不再被调用
