# Solo 记忆功能实现计划

## 一、架构总览

```
原始消息 ──压缩──▶ 摘要(summaries) ──N轮记忆提取──▶ 记忆(solo_memories)
   │                    │                              │
   ▼                    ▼                              ▼
context_items       context_items                 context_items
(message)           (summary_ref)                 (memory_ref)
                                                    │
                                           ┌───────┴────────┐
                                           ▼                ▼
                                      SQLite 索引       MD 文件详情
                                   (快速浏览/检索)    (完整 JSON)
```

记忆层在压缩层之上，形成两级层次：
- **Tier 1**（已有）：N 条 raw messages → 1 条 summary（`CompressionService`）
- **Tier 2**（新增）：N 条 summary → 1 条 memory（`SoloMemoryService`）

---

## 二、数据库变更（database_helper.dart → version 11）

### 2.1 新增 `solo_memories` 表

```sql
CREATE TABLE solo_memories (
  id TEXT PRIMARY KEY,                    -- "mem_a1b2c3d4e5f6"
  session_id TEXT NOT NULL,               -- = solo_sessions.id (ai_role_name)
  brief TEXT NOT NULL,                    -- 一句话概括（替换压缩内容用）
  role_state_snapshot_json TEXT,          -- 角色重要状态快照
  tags TEXT NOT NULL DEFAULT '',          -- 逗号分隔：important_event,important_result,cross_day
  time_range_start REAL,                  -- 覆盖时间范围起始（Unix timestamp）
  time_range_end REAL,                    -- 覆盖时间范围结束
  source_summary_ids_json TEXT NOT NULL,  -- 被消耗的摘要 ID 列表（JSON array）
  memory_count INTEGER NOT NULL DEFAULT 0,-- 序号（该 session 的第几个记忆）
  md_file_path TEXT NOT NULL,             -- 相对路径，如 "memories/mem_a1b2c3d4e5f6.md"
  created_at REAL NOT NULL,
  FOREIGN KEY (session_id) REFERENCES solo_sessions(id)
);
CREATE INDEX idx_memories_session ON solo_memories(session_id, created_at DESC);
```

### 2.2 summaries 表增加字段

```sql
ALTER TABLE summaries ADD COLUMN memory_id TEXT;
-- memory_id 非空表示该摘要已被记忆消费
ALTER TABLE summaries ADD COLUMN context_item_id TEXT;
-- context_item_id 指向 summary 对应的 summary_ref context_items 行
-- 在 CompressionService.saveCompressionResult 中写入
```

### 2.3 v11 迁移逻辑

```dart
if (oldVersion < 11) {
  await db.execute('''CREATE TABLE IF NOT EXISTS solo_memories (...)...''');
  await db.execute('ALTER TABLE summaries ADD COLUMN memory_id TEXT');
  await db.execute('ALTER TABLE summaries ADD COLUMN context_item_id TEXT');
  // 新的 app_config 默认项由 _insertAppConfigDefaults 在 onCreate 中处理
  // 同时需要修改 CompressionService.saveCompressionResult，
  // 在插入 summaries 行时写入 context_item_id
}
```

---

## 三、配置项（app_config）

在 `database_helper.dart` 的 `_insertAppConfigDefaults` 中增加：

```dart
'solo_memory_rounds': '5',           // 几轮压缩触发一次记忆提取（用户可修改）
'solo_memory_recent_keep': '3',      // 上下文中保留最近几条 memory_ref（不参与替换）
'solo_memory_max_context': '10',     // 上下文中最多保留几条 memory_ref（超出部分停用）
'solo_memory_model': 'qwen-plus',    // 记忆提取用的模型
```

在 `AppConfigService` 增加 getter：

```dart
int get soloMemoryRounds {
  final v = int.tryParse(_get('solo_memory_rounds')) ?? 5;
  return v.clamp(2, 20); // 最少 2 轮，最多 20 轮，防止过于频繁或过于稀疏
}
int get soloMemoryRecentKeep => int.tryParse(_get('solo_memory_recent_keep')) ?? 3;
int get soloMemoryMaxContext => int.tryParse(_get('solo_memory_max_context')) ?? 10;
String get soloMemoryModel => _get('solo_memory_model');
```

---

## 四、新建文件

### 4.1 `lib/services/solo_memory_service.dart`

核心服务，管理记忆的提取、存储、检索。

```dart
class SoloMemoryService {
  static final SoloMemoryService instance = SoloMemoryService._();
  SoloMemoryService._();

  /// 防并发提取锁（同一个 session 同时只能有一个提取在进行）
  final Set<String> _extractingSessions = {};

  // ==================== 记忆提取 ====================

  /// 检查是否需要提取记忆，如果需要则执行
  /// 在 CompressionService.saveCompressionResult 之后调用
  Future<void> checkAndExtract({required String sessionId});

  /// 执行一次记忆提取
  /// 输入：最近 N 条活跃的、未被记忆消费的摘要
  /// 输出：记忆 JSON → MD 文件 + SQLite 记录 + context_item 更新
  Future<SoloMemory?> extractMemory({
    required String sessionId,
    required List<Map<String, dynamic>> sourceSummaries,
  });

  // ==================== 记忆检索（Agent 工具用）====================

  /// 根据 memory_id 获取 MD 文件完整内容
  Future<String?> getMemoryDetail(String memoryId);

  /// 根据 memory_id 获取 SQLite 简要记录
  Future<Map<String, dynamic>?> getMemoryBrief(String memoryId);

  /// 获取某 session 的所有记忆简要列表（用于用户浏览）
  Future<List<Map<String, dynamic>>> listMemories(String sessionId);

  // ==================== 内部方法 ====================

  /// 计算 N 条摘要的时间跨度，检测是否跨天、大时间间隔
  TimeSpanInfo _analyzeTimeSpan(List<Map<String, dynamic>> summaries);

  /// 调用记忆提取 Agent（AI 调用）
  Future<MemoryExtractionResult> _callMemoryAgent({
    required List<Map<String, dynamic>> summaries,
    required TimeSpanInfo timeSpan,
    required AIModel model,
  });

  /// 写入 MD 文件
  Future<String> _writeMdFile(String memoryId, Map<String, dynamic> fullData);

  /// 将 memory_ref 写入 context_items + 停用被消费的 summary_ref
  Future<void> _replaceSummariesWithMemory({
    required String sessionId,
    required String memoryId,
    required String brief,
    required List<String> consumedSummaryItemIds,
  });
}
```

### 4.2 数据结构定义

```dart
// 时间跨度分析结果
class TimeSpanInfo {
  final DateTime startTime;
  final DateTime endTime;
  final bool isCrossDay;        // 是否跨天
  final bool hasLargeGap;       // 是否有超过 6 小时的间隔
  final List<String> autoTags;  // 自动打的标签
}

// 记忆提取 Agent 返回的 JSON 结构
class MemoryExtractionResult {
  final String brief;                            // 一句话概括
  final List<MemoryListItem> list;               // 重要事件/结果列表
  final Map<String, dynamic> roleStateSnapshot;  // 角色状态快照
  final List<String> tags;                       // 标签
}

class MemoryListItem {
  final String time;       // 事件时间
  final String type;       // "important_event" | "important_result"
  final String content;    // 事件/结果描述
}
```

### 4.3 记忆提取 Agent 的 System Prompt

```
你是记忆提取器。输入是连续 N 轮对话的压缩摘要（JSON 数组）。
请基于这些摘要，提取结构化记忆。

要求：
1. 只基于输入，不得添加新事实
2. brief 是一句话概括这 N 轮摘要的核心内容（用于替换上下文中的摘要）
3. list 是重要事件/结果列表，每个元素必须包含：
   - time: 发生时间（如果输入中没有精确时间，从摘要的 created_at 推算）
   - type: "important_event" 或 "important_result"
   - content: 一句话描述
4. role_state_snapshot 是角色当前状态快照，格式：
   {role_name: {mood, location, status, goals}}

时间判定规则（会由系统预先分析并告知）：
- 如果这些摘要跨越了多个自然日 → 打上 cross_day 标签
- 如果对话中有明确的重要事件（决定、转折、信息获取）→ 打上 important_event 标签
- 如果对话产生了明确结果（任务完成、问题解决、关系变化）→ 打上 important_result 标签
- 如果时间无明显特殊性且无重要事项 → list 可以只有一个元素，一句话概括全部

返回 JSON 对象，字段必须包含：
- brief: string
- list: [{time: string, type: string, content: string}]
- role_state_snapshot: {string: {mood?: string, location?: string, status?: string, goals?: string[]}}
- tags: string[]

不要输出 JSON 以外内容。
```

### 4.4 记忆提取 Agent 的调用消息构建

```dart
Map<String, dynamic> _buildMemoryExtractionRequest({
  required List<Map<String, dynamic>> summaries,
  required TimeSpanInfo timeSpan,
}) {
  // 将摘要整理为 Agent 输入
  final summaryTexts = summaries.map((s) => jsonEncode({
    'summary_id': s['id'],
    'summary_text': s['summary_text'],
    'facts': _parseJson(s['facts_json']),
    'decisions': _parseJson(s['decisions_json']),
    'role_state': _parseJson(s['role_state_json']),
    'created_at': s['created_at'],
  })).toList();

  // 预先分析的时间信息
  final timeContext = '''
时间上下文：
- 起始时间：${timeSpan.startTime}
- 结束时间：${timeSpan.endTime}
- 是否跨天：${timeSpan.isCrossDay}
- 大时间间隔：${timeSpan.hasLargeGap}
- 系统自动标签：${timeSpan.autoTags.join(', ')}
''';

  final payload = jsonEncode({
    'time_context': timeContext,
    'summaries': summaryTexts,
  });

  return {
    'system_prompt': MEMORY_EXTRACTION_PROMPT,
    'messages': [jsonEncode({'role': 'user', 'content': payload})],
  };
}
```

---

## 五、MD 文件存储

### 5.1 目录结构

```
{app_documents_dir}/memories/
  mem_a1b2c3d4e5f6.md
  mem_b2c3d4e5f6a7.md
  ...
```

### 5.2 MD 文件内容格式

每个 MD 文件存储完整 JSON（为后续扩展留 human-readable markdown 头部）：

```markdown
# 记忆 mem_a1b2c3d4e5f6

**时间范围**：2026-05-10 14:30 ~ 2026-05-10 16:45
**标签**：cross_day, important_event

---

## 简要概括

用户和小明讨论了周末去爬山的计划...

## 重要事件

| 时间 | 类型 | 内容 |
|------|------|------|
| 2026-05-10 14:30 | important_event | 用户提出周末爬山的想法 |
| 2026-05-10 16:00 | important_result | 确定了周六早上8点在香山集合 |

## 角色状态

- 小明：兴奋、期待，在家
- 用户：积极，在公司

## 原始数据

```json
{
  "brief": "...",
  "list": [...],
  "role_state_snapshot": {...},
  "tags": [...],
  "source_summary_ids": [...],
  "time_range": {"start": ..., "end": ...}
}
```
```

`FileStorageService` 新增 `memories` 目录支持：

```dart
Future<Directory> get _memoriesDir async {
  final dir = await _appDir;
  final d = Directory(path.join(dir.path, 'memories'));
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<void> saveMemory(String id, String content) async {
  final dir = await _memoriesDir;
  await File(path.join(dir.path, '$id.md')).writeAsString(content);
}

Future<String?> readMemory(String id) async {
  final dir = await _memoriesDir;
  final file = File(path.join(dir.path, '$id.md'));
  return await file.exists() ? await file.readAsString() : null;
}
```

---

## 六、上下文构建修改

### 6.1 ContextBuilderService 修改

**关键设计决策**：`memory_ref` 存在 `context_items` 表中（`item_type = 'memory_ref'`），通过 `chat_state` 的 `context_history` 加载。ContextBuilder 在构建时遍历 `context_history`，按 `item_type` 分流处理。

```
当前注入顺序（buildEffectiveContext）：
1. summary_history（summaries 表 status='active'）→ 转 system 消息
2. context_history 中未被覆盖的 message items → user/assistant 消息

修改后注入顺序：
1. context_history 中 item_type='memory_ref' 的活跃项 → system 消息（最前）
2. summary_history 中 status='active' 且 memory_id IS NULL → system 消息
3. context_history 中 item_type='message' 的未被覆盖项 → user/assistant 消息
```

**ContextBuilder.buildEffectiveContext 修改点**：

```dart
List<String> buildEffectiveContext({
  required Map<String, dynamic> chatState,
  int recentKeep = 12,
}) {
  final contextHistory = ...;
  final summaryHistory = ...;

  final blocks = <Map<String, dynamic>>[];

  // ★新增：加载 memory_ref items
  final memoryRefs = contextHistory
      .where((m) => (m['type'] ?? m['item_type'] ?? '') == 'memory_ref')
      .toList();
  for (final ref in memoryRefs) {
    blocks.add({
      'messages': [_memoryRefToContextMessage(ref)],
      'priority': 'high',
      'source': 'memory',
    });
  }

  // 活跃摘要（仅加载未被记忆消费的）
  final activeSummaries = summaryHistory
      .where((s) => (s['status'] ?? 'active') == 'active'
                 && (s['memory_id'] == null || (s['memory_id'] as String).isEmpty))
      .toList()..sort(...);
  for (var s in activeSummaries) {
    blocks.add({...});
  }

  // 原始消息（跳过被摘要覆盖 + 被记忆覆盖的）
  // ...现有逻辑...
}
```

`memory_ref` 转为上下文消息的格式：

```dart
String _memoryRefToContextMessage(Map<String, dynamic> item) {
  // item['content'] 存储的是 JSON 字符串: {"memory_id":"mem_xxx","brief":"..."}
  Map<String, dynamic> contentObj;
  try {
    contentObj = jsonDecode(item['content'] ?? '{}');
  } catch (_) {
    contentObj = {};
  }
  final obj = <String, dynamic>{
    'type': 'memory_context',
    'memory_id': contentObj['memory_id'] ?? '',
    'brief': contentObj['brief'] ?? '',
    'available_detail': true,             // 告知 LLM 可以获取详情
  };
  return jsonEncode({'role': 'system', 'content': jsonEncode(obj)});
}
```

### 6.2 context_items 中 memory_ref 的 content 格式

```json
{
  "memory_id": "mem_a1b2c3d4e5f6",
  "brief": "用户和小明讨论了周末爬山的计划，确定了集合时间地点"
}
```

ContextBuilder 解析此 JSON，提取 `memory_id` 和 `brief`，构建给 LLM 的上下文消息。

---

## 七、Agent 工具（Function Calling）

### 7.1 工具定义

聊天 Agent 需要注册两个记忆工具：

**工具 1：get_memory_detail**

```json
{
  "name": "get_memory_detail",
  "description": "获取记忆的完整详细内容。当需要回忆过去对话的具体细节时调用。",
  "parameters": {
    "type": "object",
    "properties": {
      "memory_id": {
        "type": "string",
        "description": "记忆 ID，从上下文的 memory_context 消息中获取"
      }
    },
    "required": ["memory_id"]
  }
}
```

实现：读取 `memories/{memory_id}.md` 文件，返回完整内容。

**工具 2：get_memory_brief**

```json
{
  "name": "get_memory_brief",  
  "description": "获取记忆的简要摘要。当需要快速浏览历史记忆时调用。",
  "parameters": {
    "type": "object",
    "properties": {
      "memory_id": {
        "type": "string", 
        "description": "记忆 ID，从上下文的 memory_context 消息中获取"
      }
    },
    "required": ["memory_id"]
  }
}
```

实现：查询 `solo_memories` 表，返回 `brief` + `tags` + `role_state_snapshot_json` + `time_range`。

### 7.2 工具调用流程

```
1. LLM 看到上下文中的 memory_context 消息:
   {"type":"memory_context","memory_id":"mem_xxx","brief":"...","available_detail":true}

2. LLM 判断需要更多上下文时，发起 function call:
   get_memory_detail(memory_id="mem_xxx")

3. 后端调用 SoloMemoryService.getMemoryDetail("mem_xxx")
   返回 MD 文件完整内容

4. 将 function_call + function_result 作为消息注入后续对话
```

### 7.3 实现位置

工具注册和执行在 `ChatAgentService`（或 Python 后端的 `chat_agent.py`）中。
如果当前没有 Function Calling 基础设施，**先实现被动注入模式**：

> 在构建上下文时，ContextBuilder 自动将最近 K 条 memory 的详细内容直接注入 system prompt，不依赖 Agent 主动调用工具。

等 Function Calling 基础设施就绪后再切换到按需调用模式。

---

## 八、压缩与记忆的集成

### 8.1 触发时机

在 `CompressionService.scheduleCompression` 的 `saveCompressionResult` 之后，增加记忆检查：

```dart
// compression_service.dart 的 try 块末尾
try {
  // ... 现有压缩逻辑 ...

  // Solo 模式：检查是否需要记忆提取
  await _maybeTriggerMemoryExtraction(chatId);
} finally { ... }

Future<void> _maybeTriggerMemoryExtraction(String chatId) async {
  // 只对 Solo 模式生效
  // 通过检查 solo_sessions 表判断
  final session = await DatabaseHelper.instance.query(
    'solo_sessions', where: 'id = ?', whereArgs: [chatId]);
  if (session.isEmpty) return;

  await SoloMemoryService.instance.checkAndExtract(sessionId: chatId);
}
```

### 8.2 checkAndExtract 逻辑

```dart
Future<void> checkAndExtract({required String sessionId}) async {
  if (_extractingSessions.contains(sessionId)) return;
  _extractingSessions.add(sessionId);
  try {
    await _doCheckAndExtract(sessionId: sessionId);
  } finally {
    _extractingSessions.remove(sessionId);
  }
}

Future<void> _doCheckAndExtract({required String sessionId}) async {
  final cfg = AppConfigService.instance;
  final memoryRounds = cfg.soloMemoryRounds; // 默认 5
  final recentKeep = cfg.soloMemoryRecentKeep; // 默认 3

  // 1. 查询活跃摘要中未被记忆消费的数量
  final activeSummaries = await _db.query(
    'summaries',
    where: 'chat_id = ? AND status = ? AND memory_id IS NULL',
    whereArgs: [sessionId, 'active'],
    orderBy: 'created_at ASC',
  );

  // 2. 数量不够则跳过
  if (activeSummaries.length < memoryRounds) return;

  // 3. 保留最近 recentKeep 条不消费（仍在上下文中使用）
  final consumable = activeSummaries.length - recentKeep;
  if (consumable < memoryRounds) return;

  // 4. 取最老的 memoryRounds 条进行记忆提取
  final source = activeSummaries.sublist(0, memoryRounds);

  // 5. 执行提取
  await extractMemory(sessionId: sessionId, sourceSummaries: source);

  // 6. 防止记忆膨胀：如果 memory_ref 超过 maxContext，停用最老的
  await _trimMemoryRefs(sessionId);
}
}

/// 停用超出数量上限的 memory_ref context_items
Future<void> _trimMemoryRefs(String sessionId) async {
  final maxContext = AppConfigService.instance.soloMemoryMaxContext;
  final allMemoryRefs = await _db.query(
    'context_items',
    where: 'chat_id = ? AND item_type = ? AND active = 1',
    whereArgs: [sessionId, 'memory_ref'],
    orderBy: 'created_at ASC',
  );
  if (allMemoryRefs.length <= maxContext) return;

  // 停用最老的
  final toDeactivate = allMemoryRefs.sublist(0, allMemoryRefs.length - maxContext);
  for (final item in toDeactivate) {
    await _db.update(
      'context_items',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [item['id']],
    );
  }
}
```

### 8.3 extractMemory 完整流程

```dart
Future<SoloMemory?> extractMemory({
  required String sessionId,
  required List<Map<String, dynamic>> sourceSummaries,
}) async {
  // 1. 分析时间跨度
  final timeSpan = _analyzeTimeSpan(sourceSummaries);

  // 2. 获取记忆提取模型
  final modelName = AppConfigService.instance.soloMemoryModel;
  final modelMap = await _db.getModelByName(modelName);
  if (modelMap == null) return null;
  final model = AIModel.fromMap(modelMap);

  // 3. 调用记忆提取 Agent
  final result = await _callMemoryAgent(
    summaries: sourceSummaries,
    timeSpan: timeSpan,
    model: model,
  );
  if (result.brief.isEmpty) return null;

  // 4. 生成 memory_id
  final memoryId = 'mem_${_uuid.v4().substring(0, 12)}';

  // 5. 构建完整 JSON 数据
  final fullData = {
    'memory_id': memoryId,
    'brief': result.brief,
    'list': result.list.map((e) => {
      'time': e.time,
      'type': e.type,
      'content': e.content,
    }).toList(),
    'role_state_snapshot': result.roleStateSnapshot,
    'tags': [...result.tags, ...timeSpan.autoTags],
    'source_summary_ids': sourceSummaries.map((s) => s['id']).toList(),
    'time_range': {
      'start': timeSpan.startTime.toIso8601String(),
      'end': timeSpan.endTime.toIso8601String(),
    },
    'created_at': DateTime.now().toIso8601String(),
  };

  // 6. 写入 SQLite（权威源，先写）——MD 写入失败时可从 SQLite JSON 重建
  final now = DateTime.now().millisecondsSinceEpoch / 1000;
  final memoryCount = await _getNextMemoryCount(sessionId);
  await _db.insert('solo_memories', {
    'id': memoryId,
    'session_id': sessionId,
    'brief': result.brief,
    'role_state_snapshot_json': jsonEncode(result.roleStateSnapshot),
    'tags': [...result.tags, ...timeSpan.autoTags].join(','),
    'time_range_start': timeSpan.startTime.millisecondsSinceEpoch / 1000,
    'time_range_end': timeSpan.endTime.millisecondsSinceEpoch / 1000,
    'source_summary_ids_json': jsonEncode(fullData['source_summary_ids']),
    'memory_count': memoryCount,
    'md_file_path': mdPath,
    'created_at': now,
  });

  // 7. 写入 MD 文件（失败不影响一致性，可从 SQLite 重建）
  final mdPath = await _writeMdFile(memoryId, fullData);

  // 8. 标记被消费的摘要（status = archived，防止重复出现在上下文）
  final summaryIds = sourceSummaries.map((s) => s['id'] as String).toList();
  for (final sid in summaryIds) {
    await _db.update(
      'summaries',
      {'memory_id': memoryId, 'status': 'archived'},
      where: 'id = ?',
      whereArgs: [sid],
    );
  }

  // 9. 替换 context_items
  //    - 停用被消费的 summary_ref items
  //    - 插入新的 memory_ref item
  final summaryRefIds = await _getSummaryRefIds(summaryIds);
  await _replaceSummariesWithMemory(
    sessionId: sessionId,
    memoryId: memoryId,
    brief: result.brief,
    consumedSummaryItemIds: summaryRefIds,
  );

  // 10. 记录 token 消耗
  // ...

  return SoloMemory(...);
}

/// 根据 summary IDs 找到对应的 summary_ref context_items
/// 
/// summary_ref 在 context_items 表中的特征是：
///   item_type = 'summary_ref' 
///   且 content 中包含 summary_id 的引用
/// 关联逻辑：压缩时 saveCompressionResult 在 context_items 中插入的
///   summary_ref.content = summary_text，id 是独立 UUID
/// 
/// 查找方法：遍历 context_items 中 item_type='summary_ref' 的行，
///   与 summaries 表的 id 做关联。更可靠的做法是在 summaries 表
///   增加 context_item_id 字段（v11 迁移时一并处理）
Future<List<String>> _getSummaryRefIds(List<String> summaryIds) async {
  if (summaryIds.isEmpty) return [];
  
  // 方案 A（推荐）：summaries 表新增 context_item_id 字段
  final refIds = <String>[];
  for (final sid in summaryIds) {
    final rows = await _db.query(
      'summaries',
      columns: ['context_item_id'],
      where: 'id = ?',
      whereArgs: [sid],
    );
    if (rows.isNotEmpty && rows.first['context_item_id'] != null) {
      refIds.add(rows.first['context_item_id'] as String);
    }
  }
  
  // 方案 B（兜底）：如果没有 context_item_id 字段，按 seq 范围匹配
  // 通过 summary 的 source_start_seq / source_end_seq 找到对应的
  // summary_ref context_items 的 seq 范围
  if (refIds.isEmpty) {
    // fallback implementation...
  }
  
  return refIds;
}
```

### 8.4 _replaceSummariesWithMemory 实现

```dart
Future<void> _replaceSummariesWithMemory({
  required String sessionId,
  required String memoryId,
  required String brief,
  required List<String> consumedSummaryItemIds,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch / 1000;

  // 1. 停用旧的 summary_ref context_items
  for (final id in consumedSummaryItemIds) {
    await _db.update(
      'context_items',
      {'active': 0},
      where: 'id = ? AND chat_id = ?',
      whereArgs: [id, sessionId],
    );
  }

  // 2. 获取最大 seq
  final maxSeqResult = await _db.rawQuery(
    'SELECT COALESCE(MAX(seq), 0) + 1 as next_seq FROM context_items WHERE chat_id = ?',
    [sessionId],
  );
  final seq = maxSeqResult.first['next_seq'] as int;

  // 3. 插入 memory_ref
  final content = jsonEncode({
    'memory_id': memoryId,
    'brief': brief,
  });

  await _db.insert('context_items', {
    'id': _uuid.v4(),
    'chat_id': sessionId,
    'seq': seq,
    'item_type': 'memory_ref',
    'role': 'system',
    'content': content,
    'priority': 'high',
    'compressible': 0,  // 记忆引用不可压缩
    'active': 1,
    'created_at': now,
  });
}
```

---

## 九、时间跨度分析

### 9.1 _analyzeTimeSpan

```dart
TimeSpanInfo _analyzeTimeSpan(List<Map<String, dynamic>> summaries) {
  final times = summaries
      .map((s) => DateTime.fromMillisecondsSinceEpoch(
            ((s['created_at'] as num?)?.toDouble() ?? 0 * 1000).toInt(),
          ))
      .toList()
    ..sort();

  final start = times.first;
  final end = times.last;

  final isCrossDay = start.year != end.year ||
      start.month != end.month ||
      start.day != end.day;

  // 检查是否有超过 6 小时的大间隔
  var hasLargeGap = false;
  for (var i = 1; i < times.length; i++) {
    if (times[i].difference(times[i - 1]).inHours >= 6) {
      hasLargeGap = true;
      break;
    }
  }

  final autoTags = <String>[];
  if (isCrossDay) autoTags.add('cross_day');
  if (hasLargeGap) autoTags.add('large_time_gap');

  return TimeSpanInfo(
    startTime: start,
    endTime: end,
    isCrossDay: isCrossDay,
    hasLargeGap: hasLargeGap,
    autoTags: autoTags,
  );
}
```

---

## 十、用户记忆浏览 UI（可选，后续迭代）

可以在 `SoloChatPage` 的 AppBar 或设置弹窗中增加"查看记忆"入口：

```
AppBar actions:
  [记忆图标] → 跳转 SoloMemoryListPage

SoloMemoryListPage:
  - 按时间倒序展示所有记忆
  - 每条记忆显示：brief, 标签 badges, 时间范围
  - 点击展开详情（MD 文件内容渲染）
  - 可选：搜索记忆内容
```

这个不是本轮必需，属于后续优化。

---

## 十一、文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/database/database_helper.dart` | 修改 | v11 迁移 + 新增 app_config 默认值 |
| `lib/services/app_config_service.dart` | 修改 | 新增 solo 记忆相关 getter |
| `lib/services/solo_memory_service.dart` | **新建** | 记忆提取/检索核心逻辑 |
| `lib/services/context_builder_service.dart` | 修改 | 处理 memory_ref，注入记忆上下文 |
| `lib/services/compression_service.dart` | 修改 | 压缩后触发记忆检查；saveCompressionResult 写入 context_item_id |
| `lib/services/file_storage_service.dart` | 修改 | 新增 memories 目录读写 |
| `lib/services/chat_agent_service.dart` | 修改 | 注册 get_memory_detail/get_memory_brief 工具 |
| `lib/pages/solo_chat_page.dart` | 修改 | AppBar 增加记忆入口（可选） |
| `lib/models/solo_memory.dart` | **新建** | SoloMemory / MemoryListItem / TimeSpanInfo 模型 |

---

## 十二、实施顺序

| 步骤 | 内容 | 依赖 |
|------|------|------|
| 1 | 数据库 v11 迁移（solo_memories 表 + summaries 加 memory_id） | 无 |
| 2 | FileStorageService 加 memories 目录支持 | 无 |
| 3 | SoloMemory / TimeSpanInfo 等模型定义 | 无 |
| 4 | AppConfigService 加 solo 记忆配置 getter | 步骤 1 |
| 5 | SoloMemoryService 核心逻辑（时间分析 + Agent 调用 + 存储） | 步骤 1-4 |
| 6 | ContextBuilderService 处理 memory_ref | 步骤 1 |
| 7 | CompressionService 集成记忆触发 | 步骤 5 |
| 8 | Agent 工具注册（get_memory_detail / get_memory_brief） | 步骤 5 |
| 9 | SoloChatPage 记忆入口 UI（可选） | 步骤 5 |

---

## 十三、注意事项

1. **记忆提取失败不影响主流程**——Agent 调用失败时静默跳过，等待下一轮
2. **记忆提取比压缩昂贵**（N 条完整摘要作为输入），默认模型用便宜的 `qwen-plus`
3. **写入顺序：SQLite → MD → context_items**——SQLite 是权威源，MD 失败可重建；不在事务中的步骤失败不影响已写入的 SQLite 数据
4. **memory_ref 不可被压缩**——`compressible = 0`，否则记忆引用会丢失
5. **第一批实现用被动注入**——ContextBuilder 直接把最近记忆注入 system prompt，不依赖 Function Calling。Agent 工具注册放到第二批
6. **同一 session 的记忆序号连续递增**——方便"第 3 段记忆"这样的引用
7. **防并发**——`_extractingSessions` Set 防止同一 session 同时两次提取
8. **防膨胀**——`solo_memory_max_context` 限制上下文中 memory_ref 数量，超出时停用最老的（memory_ref 被停用但 SQLite + MD 数据保留，可通过 Agent 工具按需查回）
9. **防乱设**——`solo_memory_rounds` 取值 `clamp(2, 20)`，避免用户设为 1 或 1000
10. **CompressionService 需配套修改**——`saveCompressionResult` 插入 summaries 行时同步写入 `context_item_id`（指向 summary_ref 的 context_items.id），供记忆消费时查找
