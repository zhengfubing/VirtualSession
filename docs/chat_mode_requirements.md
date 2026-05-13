# 三种聊天模式需求文档

## 一、模式定义

| 模式 | 英文名 | 场景数 | 角色数 | 记忆支持 | 说明 |
|------|--------|--------|--------|----------|------|
| 独幕 | Solo | 1 | 1 | 预留 | 单场景单角色，深度一对一沉浸体验 |
| 群像 | Ensemble | 1 | N | 否 | 单场景多角色，群像剧式互动 |
|  saga | Saga | N | N | 否 | 多场景多角色，宏大叙事世界 |

## 二、数据库需求

### 2.1 新建表：chat_modes
存储三种模式的配置信息：
- 模式标识、名称、描述、图标
- 场景配置：是否允许多场景
- 角色配置：是否允许多角色、最少/最多角色数
- 记忆配置：是否开启长久记忆、记忆类型（预留字段）
- SystemPrompt模板标识
- 排序字段

### 2.2 修改表：chats
- 增加 mode_id 字段，标识当前会话的模式
- 增加 role_name 字段，Solo模式存储单个角色名

### 2.3 修改表：world_chats
- 增加 mode_id 字段，默认为 saga 模式

## 三、数据模型需求

### 3.1 ChatMode 模型
对应 chat_modes 表的数据结构。

### 3.2 修改 Chat 模型
增加 mode_id 和 role_name 字段。

## 四、SystemPrompt 需求

### 4.1 Solo 模式 的 SystemPrompt 模板（单角色版本，创建一个新的模板标识）
基于现有单场景多角色模板，简化为单角色版本：
- 只针对一个角色进行设定
- 简化参与者相关逻辑
- 保持输出格式一致

### 4.2 Ensemble 模式 SystemPrompt
复用现有的单场景多角色模板。

### 4.3 Saga 模式 SystemPrompt
复用现有的多场景多角色模板。

## 五、功能需求

### 5.1 创建会话页面
- 第一步：选择聊天模式弹窗
  - Solo 模式：
  - Ensemble 模式：
  - Saga 模式：
跳转对应创建页面

### 5.2 会话列表显示
- 显示会话名称
- 显示模式名称（独幕/群像/ saga）
- Solo 模式额外显示角色名

### 5.3 会话创建逻辑
- Solo 模式：创建 chats 表记录，mode_id='solo'，存储 role_name
- Ensemble 模式：创建 chats 表记录，mode_id='ensemble'
- Saga 模式：创建 world_chats 表记录，mode_id='saga'

### 5.4 Prompt 构建逻辑
根据会话的 mode_id 选择对应的 SystemPrompt 模板：
- solo → Solo 模板
- ensemble → Ensemble 模板
- saga → Saga 模板

## 六、文件变更清单

### 新建文件
1. `lib/models/chat_mode.dart`
2. `lib/database/chat_mode_dao.dart`

### 修改文件
1. `lib/models/chat.dart`
2. `lib/database/database_helper.dart`（数据库迁移 version 9）
3. `lib/services/prompt_builder_service.dart`
4. `lib/services/chat_state_service.dart`
5. `lib/pages/create_chat_page.dart`
6. `lib/pages/all_chats_page.dart`

## 七、数据库迁移内容（version 9）

1. 创建 chat_modes 表
2. 插入三种模式的默认数据
3. chats 表增加 mode_id 和 role_name 字段
4. world_chats 表增加 mode_id 字段
