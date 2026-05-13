import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../services/file_storage_service.dart';
import '../services/log_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static const _dbFileName = 'aichat.db';

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(_dbFileName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 11,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. 提示词类型表
    await db.execute('''
      CREATE TABLE prompt_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type_name TEXT NOT NULL UNIQUE
      )
    ''');

    // 2. 提示词文件表
    await db.execute('''
      CREATE TABLE prompts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        prompt_type TEXT NOT NULL,
        UNIQUE(file_name, prompt_type)
      )
    ''');

    // 3. 聊天会话表
    await db.execute('''
      CREATE TABLE chats (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        scene_prompt_id TEXT NOT NULL DEFAULT 'empty',
        sender_id TEXT NOT NULL DEFAULT 'empty',
        role_setting_prompt_ids_json TEXT NOT NULL,
        mode_id TEXT NOT NULL DEFAULT 'ensemble',
        role_name TEXT NOT NULL DEFAULT '',
        last_compaction_at REAL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        deleted_at REAL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_chats_updated_at ON chats(updated_at DESC)',
    );

    // 4. 世界聊天会话表
    await db.execute('''
      CREATE TABLE world_chats (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        world_scene_id TEXT NOT NULL,
        mode_id TEXT NOT NULL DEFAULT 'saga',
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        deleted_at REAL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_world_chats_updated_at ON world_chats(updated_at DESC)',
    );

    // 4.1 世界聊天角色场景分配表
    await db.execute('''
      CREATE TABLE world_chat_roles (
        id TEXT PRIMARY KEY,
        world_chat_id TEXT NOT NULL,
        role_name TEXT NOT NULL,
        scene_name TEXT NOT NULL,
        created_at REAL NOT NULL,
        UNIQUE(world_chat_id, role_name)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_wcr_chat ON world_chat_roles(world_chat_id)',
    );

    // 5. 展示消息表
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        role TEXT NOT NULL,
        sender_name TEXT,
        content TEXT NOT NULL,
        scene TEXT NOT NULL DEFAULT '',
        payload_json TEXT NOT NULL,
        deleted_at REAL,
        created_at REAL NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_messages_chat ON messages(chat_id, deleted_at, created_at)',
    );

    // 6. 上下文消息表
    await db.execute('''
      CREATE TABLE context_items (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        item_type TEXT NOT NULL DEFAULT 'message',
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        priority TEXT NOT NULL DEFAULT 'normal',
        compressible INTEGER NOT NULL DEFAULT 1,
        active INTEGER NOT NULL DEFAULT 1,
        created_at REAL NOT NULL,
        UNIQUE(chat_id, seq)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_ctx_chat_type_active ON context_items(chat_id, item_type, active, seq)',
    );

    // 7. 摘要表
    await db.execute('''
      CREATE TABLE summaries (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        level TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        source_start_seq INTEGER NOT NULL DEFAULT 0,
        source_end_seq INTEGER NOT NULL DEFAULT 0,
        source_message_ids_json TEXT NOT NULL,
        based_on_context_version INTEGER NOT NULL DEFAULT 0,
        token_estimate_before INTEGER NOT NULL DEFAULT 0,
        token_estimate_after INTEGER NOT NULL DEFAULT 0,
        summary_text TEXT NOT NULL,
        facts_json TEXT NOT NULL,
        decisions_json TEXT NOT NULL,
        open_items_json TEXT NOT NULL,
        role_state_json TEXT NOT NULL,
        tool_memory_refs_json TEXT NOT NULL,
        memory_id TEXT,
        context_item_id TEXT,
        created_at REAL NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_chat_level ON summaries(chat_id, level, status, created_at)',
    );

    // 8. 对话轮次表
    await db.execute('''
      CREATE TABLE rounds (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        status TEXT NOT NULL,
        model_name TEXT NOT NULL,
        stream INTEGER NOT NULL DEFAULT 1,
        enable_thinking INTEGER NOT NULL DEFAULT 0,
        current_sender_id TEXT NOT NULL DEFAULT 'empty',
        prompt_snapshot_json TEXT NOT NULL,
        final_answer_message_id TEXT,
        final_reasoning TEXT NOT NULL DEFAULT '',
        error_message TEXT,
        started_at REAL NOT NULL,
        ended_at REAL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_rounds_chat_time ON rounds(chat_id, started_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_rounds_status ON rounds(status, started_at DESC)',
    );

    // 9. 轮次事件表
    await db.execute('''
      CREATE TABLE round_events (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        round_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        kind TEXT NOT NULL,
        stage TEXT NOT NULL,
        direction TEXT NOT NULL,
        model_name TEXT,
        payload_json TEXT NOT NULL,
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL,
        UNIQUE(round_id, seq)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_round_events_chat ON round_events(chat_id, created_at)',
    );

    // 10. Token消耗明细表
    await db.execute('''
      CREATE TABLE token_usage_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT,
        round_id TEXT,
        agent_type TEXT NOT NULL,
        model_name TEXT,
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_token_usage_chat_round ON token_usage_events(chat_id, round_id)',
    );
    await db.execute(
      'CREATE INDEX idx_token_usage_created ON token_usage_events(created_at)',
    );

    // 11. Token累计统计表
    await db.execute('''
      CREATE TABLE token_usage_totals (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        agent_type TEXT NOT NULL,
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        UNIQUE(chat_id, agent_type)
      )
    ''');

    // 12. TTS音色表（角色-音色映射）
    await db.execute('''
      CREATE TABLE voices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        voice_name TEXT NOT NULL DEFAULT '',
        deleted INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        deleted_at REAL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_voices_deleted ON voices(deleted, created_at DESC)',
    );

    // 13. 阿里云默认音色表
    await db.execute('''
      CREATE TABLE aliyun_default_voices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        language TEXT NOT NULL DEFAULT 'zh',
        scene TEXT,
        updated_at REAL NOT NULL
      )
    ''');

    // 14. AI模型配置表
    await db.execute('''
      CREATE TABLE ai_models (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        base_url TEXT NOT NULL,
        api_key TEXT NOT NULL,
        is_active INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 15. TTS配置表
    await db.execute('''
      CREATE TABLE tts_config (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at REAL NOT NULL
      )
    ''');

    // 16. 应用配置表
    await db.execute('''
      CREATE TABLE app_config (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at REAL NOT NULL
      )
    ''');

    // 17. 主题配置表
    await db.execute('''
      CREATE TABLE themes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        header_bg_color INTEGER NOT NULL,
        header_icon_color INTEGER NOT NULL,
        bottom_bg_color INTEGER NOT NULL,
        bottom_icon_color INTEGER NOT NULL,
        page_bg_color INTEGER NOT NULL,
        bg_image_path TEXT,
        bg_video_path TEXT,
        is_active INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL
      )
    ''');

    // 18. 字体配置表
    await db.execute('''
      CREATE TABLE fonts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        family_name TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        preview_text TEXT NOT NULL DEFAULT ''
      )
    ''');

    // 19. 聊天模式表
    await db.execute('''
      CREATE TABLE chat_modes (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        icon TEXT NOT NULL DEFAULT 'chat_bubble_outline',
        multi_scene INTEGER NOT NULL DEFAULT 0,
        multi_role INTEGER NOT NULL DEFAULT 0,
        min_roles INTEGER NOT NULL DEFAULT 1,
        max_roles INTEGER NOT NULL DEFAULT 1,
        memory_enabled INTEGER NOT NULL DEFAULT 0,
        memory_type TEXT NOT NULL DEFAULT 'none',
        system_prompt_template TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 20. Solo 会话表
    await db.execute('''
      CREATE TABLE solo_sessions (
        id TEXT PRIMARY KEY,
        ai_role_name TEXT NOT NULL UNIQUE,
        user_role_name TEXT NOT NULL,
        scene_prompt_id TEXT NOT NULL DEFAULT 'empty',
        status TEXT NOT NULL DEFAULT 'active',
        system_prompt_json TEXT NOT NULL DEFAULT '{}',
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        deleted_at REAL
      )
    ''');

    // 21. Solo 记忆表
    await db.execute('''
      CREATE TABLE solo_memories (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        brief TEXT NOT NULL,
        role_state_snapshot_json TEXT,
        tags TEXT NOT NULL DEFAULT '',
        time_range_start REAL,
        time_range_end REAL,
        source_summary_ids_json TEXT NOT NULL,
        memory_count INTEGER NOT NULL DEFAULT 0,
        md_file_path TEXT NOT NULL,
        created_at REAL NOT NULL,
        FOREIGN KEY (session_id) REFERENCES solo_sessions(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_memories_session ON solo_memories(session_id, created_at DESC)',
    );

    await _insertDefaultData(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tts_config (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at REAL NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_config (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at REAL NOT NULL
        )
      ''');
      await _insertAppConfigDefaults(db);
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS world_chat_roles (
          id TEXT PRIMARY KEY,
          world_chat_id TEXT NOT NULL,
          role_name TEXT NOT NULL,
          scene_name TEXT NOT NULL,
          created_at REAL NOT NULL,
          UNIQUE(world_chat_id, role_name)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_wcr_chat ON world_chat_roles(world_chat_id)',
      );
    }
    if (oldVersion < 5) {
      // 简化 voices 表：移除 voice_type, voice_uuid, default_voice_id, prompt, target_model, language
      // 新建简化表并迁移数据
      await db.execute('''
        CREATE TABLE voices_new (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          voice_name TEXT NOT NULL DEFAULT '',
          deleted INTEGER NOT NULL DEFAULT 0,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          deleted_at REAL
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_voices_deleted_new ON voices_new(deleted, created_at DESC)',
      );
      // 迁移数据：default_voice_id 或 voice_uuid 映射到 voice_name
      await db.execute('''
        INSERT INTO voices_new (id, name, voice_name, deleted, created_at, updated_at, deleted_at)
        SELECT id, name,
          CASE
            WHEN voice_type = 'default' AND default_voice_id IS NOT NULL THEN default_voice_id
            WHEN voice_type = 'custom' AND voice_uuid IS NOT NULL THEN voice_uuid
            ELSE ''
          END,
          deleted, created_at, updated_at, deleted_at
        FROM voices
      ''');
      await db.execute('DROP TABLE voices');
      await db.execute('ALTER TABLE voices_new RENAME TO voices');
      // 清理 tts_config 中的 voice_design 相关配置
      await db.delete('tts_config', where: "key LIKE 'voice_design_%'");
      await db.delete('tts_config', where: "key = 'tts_custom_voice_model'");
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS themes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          header_bg_color INTEGER NOT NULL,
          header_icon_color INTEGER NOT NULL,
          bottom_bg_color INTEGER NOT NULL,
          bottom_icon_color INTEGER NOT NULL,
          page_bg_color INTEGER NOT NULL,
          bg_image_path TEXT,
          is_active INTEGER NOT NULL DEFAULT 0,
          created_at REAL NOT NULL
        )
      ''');
      await _insertDefaultTheme(db);
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS fonts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          family_name TEXT NOT NULL UNIQUE,
          display_name TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          preview_text TEXT NOT NULL DEFAULT ''
        )
      ''');
      await _insertDefaultFonts(db);
    }
    if (oldVersion < 8) {
      // 为主题表添加视频背景路径字段
      await db.execute('''
        ALTER TABLE themes ADD COLUMN bg_video_path TEXT
      ''');
    }
    if (oldVersion < 9) {
      // 创建聊天模式表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_modes (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          icon TEXT NOT NULL DEFAULT 'chat_bubble_outline',
          multi_scene INTEGER NOT NULL DEFAULT 0,
          multi_role INTEGER NOT NULL DEFAULT 0,
          min_roles INTEGER NOT NULL DEFAULT 1,
          max_roles INTEGER NOT NULL DEFAULT 1,
          memory_enabled INTEGER NOT NULL DEFAULT 0,
          memory_type TEXT NOT NULL DEFAULT 'none',
          system_prompt_template TEXT NOT NULL DEFAULT '',
          sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      // chats 表增加 mode_id 和 role_name 字段
      await db.execute("ALTER TABLE chats ADD COLUMN mode_id TEXT NOT NULL DEFAULT 'ensemble'");
      await db.execute("ALTER TABLE chats ADD COLUMN role_name TEXT NOT NULL DEFAULT ''");
      // world_chats 表增加 mode_id 字段
      await db.execute("ALTER TABLE world_chats ADD COLUMN mode_id TEXT NOT NULL DEFAULT 'saga'");
      // 插入默认模式数据
      await _insertDefaultChatModes(db);
      // 插入 Solo 系统提示词配置
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      await db.insert('app_config', {
        'key': 'solo_system_prompt_id',
        'value': 'SoloSystem',
        'updated_at': now,
      });
    }
    if (oldVersion < 10) {
      // 1. 创建 solo_sessions 表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS solo_sessions (
          id TEXT PRIMARY KEY,
          ai_role_name TEXT NOT NULL UNIQUE,
          user_role_name TEXT NOT NULL,
          scene_prompt_id TEXT NOT NULL DEFAULT 'empty',
          status TEXT NOT NULL DEFAULT 'active',
          system_prompt_json TEXT NOT NULL DEFAULT '{}',
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          deleted_at REAL
        )
      ''');

      // 2. 迁移现有 Solo chats 到 solo_sessions
      await _migrateSoloChatsToSessions(db);

      // 3. 更新 messages / context_items / summaries 的 chat_id 引用
      await _migrateSoloReferences(db);

      // 4. 更新 Solo 模式的 memory 标志
      await db.update(
        'chat_modes',
        {'memory_enabled': 1, 'memory_type': 'time_aware'},
        where: 'id = ?',
        whereArgs: ['solo'],
      );
    }
    if (oldVersion < 11) {
      // 1. 创建 solo_memories 表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS solo_memories (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          brief TEXT NOT NULL,
          role_state_snapshot_json TEXT,
          tags TEXT NOT NULL DEFAULT '',
          time_range_start REAL,
          time_range_end REAL,
          source_summary_ids_json TEXT NOT NULL,
          memory_count INTEGER NOT NULL DEFAULT 0,
          md_file_path TEXT NOT NULL,
          created_at REAL NOT NULL,
          FOREIGN KEY (session_id) REFERENCES solo_sessions(id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_memories_session ON solo_memories(session_id, created_at DESC)',
      );

      // 2. summaries 表增加 memory_id 和 context_item_id 字段
      await db.execute("ALTER TABLE summaries ADD COLUMN memory_id TEXT");
      await db.execute("ALTER TABLE summaries ADD COLUMN context_item_id TEXT");
    }
  }

  Future _insertDefaultData(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;

    // 插入提示词类型
    await db.insert('prompt_types', {'type_name': 'roleSettingPrompt'});
    await db.insert('prompt_types', {'type_name': 'scenePrompt'});
    await db.insert('prompt_types', {'type_name': 'systemPrompt'});
    await db.insert('prompt_types', {'type_name': 'world'});

    await _importSeedData(db);

    // 插入默认聊天模式
    await _insertDefaultChatModes(db);

    // 插入阿里云默认音色
    final voices = [
      {
        'id': 'Cherry',
        'name': '芊悦',
        'description': '阳光积极、亲切自然小姐姐（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Serena',
        'name': '苏瑶',
        'description': '温柔小姐姐（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Ethan',
        'name': '晨煦',
        'description': '标准普通话，带部分北方口音。阳光、温暖、活力、朝气（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Chelsie',
        'name': '千雪',
        'description': '二次元虚拟女友（女性）',
        'language': 'zh',
        'scene': '二次元',
        'updated_at': now,
      },
      {
        'id': 'Momo',
        'name': '茉兔',
        'description': '撒娇搞怪，逗你开心（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Vivian',
        'name': '十三',
        'description': '拽拽的、可爱的小暴躁（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Moon',
        'name': '月白',
        'description': '率性帅气的月白（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Maia',
        'name': '四月',
        'description': '知性与温柔的碰撞（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Kai',
        'name': '凯',
        'description': '耳朵的一场SPA（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Nofish',
        'name': '不吃鱼',
        'description': '不会翘舌音的设计师（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Bella',
        'name': '萌宝',
        'description': '喝酒不打醉拳的小萝莉（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Jennifer',
        'name': '詹妮弗',
        'description': '品牌级、电影质感般美语女声（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Ryan',
        'name': '甜茶',
        'description': '节奏拉满，戏感炸裂，真实与张力共舞（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Katerina',
        'name': '卡捷琳娜',
        'description': '御姐音色，韵律回味十足（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Aiden',
        'name': '艾登',
        'description': '精通厨艺的美语大男孩（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Eldric Sage',
        'name': '沧明子',
        'description': '沉稳睿智的老者，沧桑如松却心明如镜（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Mia',
        'name': '乖小妹',
        'description': '温顺如春水，乖巧如初雪（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Mochi',
        'name': '沙小弥',
        'description': '聪明伶俐的小大人，童真未泯却早慧如禅（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Bellona',
        'name': '燕铮莺',
        'description': '声音洪亮，吐字清晰，人物鲜活，听得人热血沸腾；金戈铁马入梦来，字正腔圆间尽显千面人声的江湖（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Vincent',
        'name': '田叔',
        'description': '一口独特的沙哑烟嗓，一开口便道尽了千军万马与江湖豪情（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Bunny',
        'name': '萌小姬',
        'description': '"萌属性"爆棚的小萝莉（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Neil',
        'name': '阿闻',
        'description': '平直的基线语调，字正腔圆的咬字发音，这就是最专业的新闻主持人（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Elias',
        'name': '墨讲师',
        'description': '既保持学科严谨性，又通过叙事技巧将复杂知识转化为可消化的认知模块（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Arthur',
        'name': '徐大爷',
        'description': '被岁月和旱烟浸泡过的质朴嗓音，不疾不徐地摇开了满村的奇闻异事（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Nini',
        'name': '邻家妹妹',
        'description': '糯米糍一样又软又黏的嗓音，那一声声拉长了的"哥哥"，甜得能把人的骨头都叫酥了（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Seren',
        'name': '小婉',
        'description': '温和舒缓的声线，助你更快地进入睡眠，晚安，好梦（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Pip',
        'name': '顽屁小孩',
        'description': '调皮捣蛋却充满童真的他来了，这是你记忆中的小新吗（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Stella',
        'name': '少女阿月',
        'description': '平时是甜到发腻的迷糊少女音，但在喊出"代表月亮消灭你"时，瞬间充满不容置疑的爱与正义（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Bodega',
        'name': '博德加',
        'description': '热情的西班牙大叔（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Sonrisa',
        'name': '索尼莎',
        'description': '热情开朗的拉美大姐（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Alek',
        'name': '阿列克',
        'description': '一开口，是战斗民族的冷，也是毛呢大衣下的暖（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Dolce',
        'name': '多尔切',
        'description': '慵懒的意大利大叔（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Sohee',
        'name': '素熙',
        'description': '温柔开朗，情绪丰富的韩国欧尼（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Ono Anna',
        'name': '小野杏',
        'description': '鬼灵精怪的青梅竹马（女性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Lenn',
        'name': '莱恩',
        'description': '理性是底色，叛逆藏在细节里——穿西装也听后朋克的德国青年（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Emilien',
        'name': '埃米尔安',
        'description': '浪漫的法国大哥哥（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Andre',
        'name': '安德雷',
        'description': '声音磁性，自然舒服、沉稳男生（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Radio Gol',
        'name': '拉迪奥·戈尔',
        'description': '足球诗人Rádio Gol！今天我要用名字为你们解说足球（男性）',
        'language': 'zh',
        'scene': '通用',
        'updated_at': now,
      },
      {
        'id': 'Jada',
        'name': '上海-阿珍',
        'description': '风风火火的沪上阿姐（女性）',
        'language': 'zh',
        'scene': '方言',
        'updated_at': now,
      },
      {
        'id': 'Dylan',
        'name': '北京-晓东',
        'description': '北京胡同里长大的少年（男性）',
        'language': 'zh',
        'scene': '方言',
        'updated_at': now,
      },
      {
        'id': 'Li',
        'name': '南京-老李',
        'description': '耐心的瑜伽老师（男性）',
        'language': 'zh',
        'scene': '方言',
        'updated_at': now,
      },
      {
        'id': 'Marcus',
        'name': '陕西-秦川',
        'description': '面宽话短，心实声沉——老陕的味道（男性）',
        'language': 'zh',
        'scene': '方言',
        'updated_at': now,
      },
      {
        'id': 'Roy',
        'name': '闽南-阿杰',
        'description': '诙谐直爽、市井活泼的台湾哥仔形象（男性）',
        'language': 'zh',
        'scene': '方言',
        'updated_at': now,
      },
      {
        'id': 'Peter',
        'name': '天津-李彼得',
        'description': '天津相声，专业捧哏（男性）',
        'language': 'zh',
        'scene': '方言',
        'updated_at': now,
      },
      {
        'id': 'Sunny',
        'name': '四川-晴儿',
        'description': '甜到你心里的川妹子（女性）',
        'language': 'zh',
        'scene': '方言',
        'updated_at': now,
      },
      {
        'id': 'Eric',
        'name': '四川-程川',
        'description': '一个跳脱市井的四川成都男子（男性）',
        'language': 'zh',
        'scene': '方言',
        'updated_at': now,
      },
      {
        'id': 'Rocky',
        'name': '粤语-阿强',
        'description': '幽默风趣的阿强，在线陪聊（男性）',
        'language': 'zh',
        'scene': '方言',
        'updated_at': now,
      },
      {
        'id': 'Kiki',
        'name': '粤语-阿清',
        'description': '甜美的港妹闺蜜（女性）',
        'language': 'zh',
        'scene': '方言',
        'updated_at': now,
      },
    ];
    for (var voice in voices) {
      await db.insert('aliyun_default_voices', voice);
    }

    // 插入默认AI模型
    final defaultModels = [
      {
        'name': 'qwen3.6-plus',
        'base_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'api_key': '',
        'is_active': 0,
      },
      {
        'name': 'qwen3-max',
        'base_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'api_key': '',
        'is_active': 1,
      },
      {
        'name': 'qwen-plus',
        'base_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'api_key': '',
        'is_active': 0,
      },
    ];
    for (var model in defaultModels) {
      await db.insert('ai_models', {
        ...model,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    // 插入TTS默认配置
    await _insertTtsConfigDefaults(db);

    // 插入应用默认配置
    await _insertAppConfigDefaults(db);

    // 插入默认主题
    await _insertDefaultTheme(db);

    // 插入默认字体
    await _insertDefaultFonts(db);
  }

  static Future<void> _insertDefaultFonts(Database db) async {
    final fonts = [
      {
        'family_name': '',
        'display_name': '系统默认',
        'description': '使用系统自带字体',
        'preview_text': '天地玄黄 宇宙洪荒',
      },
      {
        'family_name': 'LXGW WenKai GB Screen',
        'display_name': '霞鹜文楷 屏幕版',
        'description': '适合屏幕阅读的文楷风格，笔画清晰，阅读舒适',
        'preview_text': '霞鹜文楷，致胜千里',
      },
      {
        'family_name': 'LXGW ZhenKai GB',
        'display_name': '霞鹜真楷',
        'description': '基于霞鹜文楷的真楷风格，更加端正工整',
        'preview_text': '真楷端正，笔墨生辉',
      },
      {
        'family_name': 'LXGW ZhenKai Slab GB',
        'display_name': '霞鹜真楷 Slab',
        'description': '真楷的衬线版本，适合长文阅读',
        'preview_text': '横平竖直，气韵生动',
      },
      {
        'family_name': 'ZhenKai GBK',
        'display_name': '真楷 GBK',
        'description': 'GBK 字符集的真楷字体，支持更多汉字',
        'preview_text': '博采众长，兼容并蓄',
      },
      {
        'family_name': 'Yozai',
        'display_name': '悠哉字体',
        'description': '轻松悠哉的手写风格，活泼有趣',
        'preview_text': '悠哉悠哉，闲适自在',
      },
      {
        'family_name': 'Xiaolai',
        'display_name': '小赖字体',
        'description': '个性鲜明的创意字体，适合标题展示',
        'preview_text': '小赖登场，别具一格',
      },
      {
        'family_name': 'Xiaolai Mono',
        'display_name': '小赖等宽',
        'description': '小赖字体的等宽版本，适合代码和对齐场景',
        'preview_text': '等宽排列，整齐划一',
      },
    ];
    for (var font in fonts) {
      await db.insert('fonts', font);
    }
  }

  static Future<void> _insertDefaultTheme(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await db.insert('themes', {
      'name': '默认主题',
      'header_bg_color': const Color(0xFFE3F2FD).toARGB32(),
      'header_icon_color': const Color(0xFF2979FF).toARGB32(),
      'bottom_bg_color': const Color(0xFFE3F2FD).toARGB32(),
      'bottom_icon_color': const Color(0xFF2979FF).toARGB32(),
      'page_bg_color': const Color(0xFFFFFFFF).toARGB32(),
      'bg_image_path': null,
      'is_active': 1,
      'created_at': now,
    });
  }

  Future _insertTtsConfigDefaults(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final defaults = {
      'tts_api_key': '',
      'tts_base_url': 'https://dashscope.aliyuncs.com/api/v1',
      'tts_model': 'qwen3-tts-flash',
      'tts_voice': 'Cherry',
      'tts_language': 'Chinese',
    };
    for (var entry in defaults.entries) {
      await db.insert('tts_config', {
        'key': entry.key,
        'value': entry.value,
        'updated_at': now,
      });
    }
  }

  Future _insertAppConfigDefaults(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final defaults = {
      'enable_thinking': 'false',
      'default_system_prompt_id': 'System',
      'agent_model_chat': 'qwen3.6-plus',
      'agent_model_tool_agent': 'qwen-plus',
      'agent_model_compression': 'qwen-plus',
      'worldchat_system_prompt_id': 'WorldSystem',
      'solo_system_prompt_id': 'SoloSystem',
      'enable_search': 'true',
      'compression_recent_keep': '12',
      'compression_a_batch': '5',
      'solo_memory_rounds': '5',
      'solo_memory_recent_keep': '3',
      'solo_memory_max_context': '10',
      'solo_memory_model': 'qwen-plus',
      'solo_max_history_rounds': '30',
    };
    for (var entry in defaults.entries) {
      await db.insert('app_config', {
        'key': entry.key,
        'value': entry.value,
        'updated_at': now,
      });
    }
  }

  static Future<void> _insertDefaultChatModes(Database db) async {
    final modes = [
      {
        'id': 'solo',
        'name': '独幕',
        'description': '单场景单角色，深度一对一沉浸体验',
        'icon': 'person',
        'multi_scene': 0,
        'multi_role': 0,
        'min_roles': 1,
        'max_roles': 1,
        'memory_enabled': 0,
        'memory_type': 'none',
        'system_prompt_template': 'solo',
        'sort_order': 0,
      },
      {
        'id': 'ensemble',
        'name': '群像',
        'description': '单场景多角色，群像剧式互动',
        'icon': 'group',
        'multi_scene': 0,
        'multi_role': 1,
        'min_roles': 1,
        'max_roles': 20,
        'memory_enabled': 0,
        'memory_type': 'none',
        'system_prompt_template': 'ensemble',
        'sort_order': 1,
      },
      {
        'id': 'saga',
        'name': 'Saga',
        'description': '多场景多角色，宏大叙事世界',
        'icon': 'auto_awesome',
        'multi_scene': 1,
        'multi_role': 1,
        'min_roles': 1,
        'max_roles': 20,
        'memory_enabled': 0,
        'memory_type': 'none',
        'system_prompt_template': 'saga',
        'sort_order': 2,
      },
    ];
    for (var mode in modes) {
      await db.insert('chat_modes', mode);
    }
  }

  /// v10 迁移：将现有 Solo chats 数据迁移到 solo_sessions 表
  static Future<void> _migrateSoloChatsToSessions(Database db) async {
    final soloChats = await db.query(
      'chats',
      where: "mode_id = ? AND deleted_at IS NULL",
      whereArgs: ['solo'],
      orderBy: 'updated_at DESC',
    );

    if (soloChats.isEmpty) return;

    // 按 ai_role_name 分组，取每组最新的那条
    final seenRoles = <String>{};
    for (final chat in soloChats) {
      final roleName = (chat['role_name'] as String? ?? '').replaceAll('.md', '');
      if (roleName.isEmpty) continue;
      if (seenRoles.contains(roleName)) continue;
      seenRoles.add(roleName);

      final sessionId = roleName;
      final userRoleName = (chat['sender_id'] as String? ?? 'empty').replaceAll('.md', '');

      // 检查是否已存在
      final existing = await db.query(
        'solo_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      if (existing.isNotEmpty) continue;

      await db.insert('solo_sessions', {
        'id': sessionId,
        'ai_role_name': roleName,
        'user_role_name': userRoleName,
        'scene_prompt_id': chat['scene_prompt_id'] ?? 'empty',
        'status': 'active',
        'system_prompt_json': '{}',
        'created_at': chat['created_at'],
        'updated_at': chat['updated_at'],
        'deleted_at': null,
      });
    }
  }

  /// v10 迁移：更新 messages / context_items / summaries 的 chat_id 引用
  static Future<void> _migrateSoloReferences(Database db) async {
    // 获取所有 solo_sessions 用于映射
    final sessions = await db.query('solo_sessions');
    if (sessions.isEmpty) return;

    // 查询所有 mode_id='solo' 的 chats
    final soloChats = await db.query(
      'chats',
      where: "mode_id = ?",
      whereArgs: ['solo'],
    );

    // 建立旧 chat_id → 新 session_id 的映射
    // 规则：chat.role_name (去掉.md) → session.id (即 ai_role_name)
    // 同一个 ai_role_name 可能有多个旧 chat，统一映射到最新的 session
    final chatIdToSessionId = <String, String>{};
    for (final chat in soloChats) {
      final roleName = (chat['role_name'] as String? ?? '').replaceAll('.md', '');
      if (roleName.isEmpty) continue;
      // 检查 session 是否存在
      final session = await db.query(
        'solo_sessions',
        where: 'id = ?',
        whereArgs: [roleName],
      );
      if (session.isNotEmpty) {
        chatIdToSessionId[chat['id'] as String] = roleName;
      }
    }

    if (chatIdToSessionId.isEmpty) return;

    // 更新 messages
    for (final entry in chatIdToSessionId.entries) {
      await db.update(
        'messages',
        {'chat_id': entry.value},
        where: 'chat_id = ?',
        whereArgs: [entry.key],
      );
      await db.update(
        'context_items',
        {'chat_id': entry.value},
        where: 'chat_id = ?',
        whereArgs: [entry.key],
      );
      await db.update(
        'summaries',
        {'chat_id': entry.value},
        where: 'chat_id = ?',
        whereArgs: [entry.key],
      );
    }
  }

  static List<String> _scanSeedAssetPaths() {
    return [
      // roleSettingPrompt
      'assets/start/roleSettingPrompt/Cheryl.md',
      'assets/start/roleSettingPrompt/Emily.md',
      'assets/start/roleSettingPrompt/laowang.md',
      'assets/start/roleSettingPrompt/lingxiaotang.md',
      'assets/start/roleSettingPrompt/xiaoming.md',
      'assets/start/roleSettingPrompt/zhoujy.md',
      // scenePrompt
      'assets/start/scenePrompt/Bedroom.md',
      'assets/start/scenePrompt/SectMainHall.md',
      'assets/start/scenePrompt/Shelter.md',
      'assets/start/scenePrompt/Street.md',
      'assets/start/scenePrompt/school.md',
      // systemPrompt
      'assets/start/systemPrompt/System.md',
      'assets/start/systemPrompt/WorldSystem.md',
      'assets/start/systemPrompt/SoloSystem.md',
      // world
      'assets/start/world/Earth.md',
      'assets/start/world/TheEndOfTheWorld.md',
      'assets/start/world/XianxiaWorld.md',
      // avatar
      'assets/start/avatar/Cheryl.jpg',
      'assets/start/avatar/Emily.jpg',
      'assets/start/avatar/System.jpg',
      'assets/start/avatar/laowang.jpg',
      'assets/start/avatar/lingxiaotang.jpg',
      'assets/start/avatar/xiaoming.jpg',
      'assets/start/avatar/zhoujy.jpg',
    ];
  }

  static (String promptType, String name)? _parseSeedPath(String assetPath) {
    final prefix = 'assets/start/';
    if (!assetPath.startsWith(prefix)) return null;

    final relative = assetPath.substring(prefix.length);
    final slashIndex = relative.indexOf('/');
    if (slashIndex < 0) return null;

    final promptType = relative.substring(0, slashIndex);
    final fileName = relative.substring(slashIndex + 1);

    final validTypes = {
      'roleSettingPrompt',
      'scenePrompt',
      'systemPrompt',
      'world',
      'avatar',
    };
    if (!validTypes.contains(promptType)) return null;

    final ext = fileName.endsWith('.md') ? '.md' : '.jpg';
    final name = fileName.substring(0, fileName.length - ext.length);
    if (name.isEmpty) return null;

    return (promptType, name);
  }

  static Future<void> _importSeedData(Database db) async {
    final fileStorage = FileStorageService();
    final assetPaths = _scanSeedAssetPaths();

    if (assetPaths.isEmpty) {
      LogService.instance.warn('未找到任何种子资源，跳过导入');
      return;
    }
    LogService.instance.info('发现 ${assetPaths.length} 个种子资源');

    for (final assetPath in assetPaths) {
      final parsed = _parseSeedPath(assetPath);
      if (parsed == null) continue;

      final (promptType, name) = parsed;

      if (promptType == 'avatar') {
        try {
          final alreadyExists = await fileStorage.hasRoleAvatar(name);
          if (alreadyExists) continue;
          final bytes = await rootBundle.load(assetPath);
          await fileStorage.saveRoleAvatar(name, bytes.buffer.asUint8List());
        } catch (e) {
          LogService.instance.error('导入头像失败 [$name]: $e');
        }
        continue;
      }

      final exists = await db.query(
        'prompts',
        where: 'file_name = ? AND prompt_type = ?',
        whereArgs: [name, promptType],
      );
      if (exists.isNotEmpty) continue;

      try {
        final content = await rootBundle.loadString(assetPath);
        if (content.trim().isEmpty) continue;

        switch (promptType) {
          case 'roleSettingPrompt':
            await fileStorage.saveRole(name, content);
            break;
          case 'scenePrompt':
            await fileStorage.saveScene(name, content);
            break;
          case 'systemPrompt':
            await fileStorage.saveSystemPrompt(name, content);
            break;
          case 'world':
            await fileStorage.saveWorld(name, content);
            break;
        }
        await db.insert('prompts', {
          'file_name': name,
          'prompt_type': promptType,
        });
      } catch (e) {
        LogService.instance.error('导入种子数据失败 [$promptType/$name]: $e');
      }
    }
  }

  Future<void> resetDatabase() async {
    LogService.instance.info('开始重置数据库...');
    if (_database != null) {
      await _database!.close();
      _database = null;
      LogService.instance.info('已关闭旧数据库连接');
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbFileName);
    LogService.instance.info('数据库路径: $path');

    // 删除所有相关文件
    final filesToDelete = [
      path,
      '$path-journal',
      '$path-wal',
      '$path-shm',
      '$path.back',
      '$path.corrupt',
    ];

    for (final filePath in filesToDelete) {
      final file = File(filePath);
      if (await file.exists()) {
        try {
          await file.delete();
          LogService.instance.info('已删除: $filePath');
        } catch (e) {
          LogService.instance.error('删除文件失败 $filePath: $e');
        }
      }
    }

    // 删除目录中的所有临时文件
    final dbDir = Directory(dbPath);
    if (await dbDir.exists()) {
      final tempFiles = dbDir
          .listSync()
          .where((f) => f.path.contains(_dbFileName))
          .toList();
      for (final file in tempFiles) {
        try {
          await file.delete();
          LogService.instance.info('已删除临时文件: ${file.path}');
        } catch (e) {
          LogService.instance.error('删除临时文件失败 ${file.path}: $e');
        }
      }
    }

    // _insertDefaultData is already called inside _createDB → onCreate
    LogService.instance.info('正在重新创建数据库...');
    await database;
    LogService.instance.info('数据库重置完成');
  }

  // ==================== 通用CRUD方法 ====================

  // 插入
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert(table, data);
  }

  // 查询所有
  Future<List<Map<String, dynamic>>> queryAll(
    String table, {
    String? orderBy,
  }) async {
    final db = await instance.database;
    return await db.query(table, orderBy: orderBy);
  }

  // 条件查询
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
  }) async {
    final db = await instance.database;
    return await db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
  }

  // 更新
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await instance.database;
    return await db.update(table, data, where: where, whereArgs: whereArgs);
  }

  // 删除
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await instance.database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  // 执行原始SQL
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    final db = await instance.database;
    return await db.rawQuery(sql, arguments);
  }

  // ==================== AI 模型表操作 ====================

  // ==================== 聊天模式表操作 ====================

  Future<List<Map<String, dynamic>>> getAllChatModes() async {
    final db = await instance.database;
    return await db.query('chat_modes', orderBy: 'sort_order ASC');
  }

  Future<Map<String, dynamic>?> getChatModeById(String id) async {
    final db = await instance.database;
    final results = await db.query(
      'chat_modes',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // 获取所有模型
  Future<List<Map<String, dynamic>>> getAllModels() async {
    final db = await instance.database;
    return await db.query('ai_models', orderBy: 'created_at DESC');
  }

  // 获取当前激活的模型
  Future<Map<String, dynamic>?> getActiveModel() async {
    final db = await instance.database;
    final results = await db.query(
      'ai_models',
      where: 'is_active = ?',
      whereArgs: [1],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // 根据名称获取模型
  Future<Map<String, dynamic>?> getModelByName(String name) async {
    final db = await instance.database;
    final results = await db.query(
      'ai_models',
      where: 'name = ?',
      whereArgs: [name],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // 根据ID获取模型
  Future<Map<String, dynamic>?> getModelById(int id) async {
    final db = await instance.database;
    final results = await db.query(
      'ai_models',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // 添加模型
  Future<int> createModel(Map<String, dynamic> model) async {
    final db = await instance.database;
    return await db.insert('ai_models', model);
  }

  // 更新模型
  Future<int> updateModel(int id, Map<String, dynamic> model) async {
    final db = await instance.database;
    return await db.update(
      'ai_models',
      model,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 删除模型
  Future<int> deleteModel(int id) async {
    final db = await instance.database;
    return await db.delete('ai_models', where: 'id = ?', whereArgs: [id]);
  }

  // 切换激活的模型
  Future<void> setActiveModel(int id) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      // 先将所有模型设为非激活
      await txn.update('ai_models', {'is_active': 0});
      // 再将指定模型设为激活
      await txn.update(
        'ai_models',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // ==================== TTS配置表操作 ====================

  // 获取单个配置值
  Future<String?> getTtsConfig(String key) async {
    final db = await instance.database;
    final results = await db.query(
      'tts_config',
      where: 'key = ?',
      whereArgs: [key],
    );
    return results.isNotEmpty ? results.first['value'] as String : null;
  }

  // 获取所有配置
  Future<Map<String, String>> getAllTtsConfig() async {
    final db = await instance.database;
    final results = await db.query('tts_config');
    return {for (var r in results) r['key'] as String: r['value'] as String};
  }

  // 保存单个配置
  Future<void> setTtsConfig(String key, String value) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await db.insert('tts_config', {
      'key': key,
      'value': value,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==================== 应用配置表操作 ====================

  Future<String?> getAppConfig(String key) async {
    final db = await instance.database;
    final results = await db.query(
      'app_config',
      where: 'key = ?',
      whereArgs: [key],
    );
    return results.isNotEmpty ? results.first['value'] as String : null;
  }

  Future<Map<String, String>> getAllAppConfig() async {
    final db = await instance.database;
    final results = await db.query('app_config');
    return {for (var r in results) r['key'] as String: r['value'] as String};
  }

  Future<void> setAppConfig(String key, String value) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await db.insert('app_config', {
      'key': key,
      'value': value,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==================== 音色表操作 ====================

  // 获取所有有效音色配置
  Future<List<Map<String, dynamic>>> getAllVoices() async {
    final db = await instance.database;
    return await db.query(
      'voices',
      where: 'deleted = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
    );
  }

  // 根据角色名获取音色配置
  Future<Map<String, dynamic>?> getVoiceByName(String name) async {
    final db = await instance.database;
    final results = await db.query(
      'voices',
      where: 'name = ? AND deleted = ?',
      whereArgs: [name, 0],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // 保存音色配置（插入或更新），以角色 name 作为唯一键
  Future<void> saveVoice(String name, String voiceName) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final existing = await getVoiceByName(name);
    if (existing != null) {
      await db.update(
        'voices',
        {'voice_name': voiceName, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [existing['id']],
      );
    } else {
      await db.insert('voices', {
        'id': name,
        'name': name,
        'voice_name': voiceName,
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
      });
    }
  }

  // 软删除音色配置
  Future<void> deleteVoice(String id) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await db.update(
      'voices',
      {'deleted': 1, 'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 获取所有阿里云默认音色
  Future<List<Map<String, dynamic>>> getAllAliyunDefaultVoices() async {
    final db = await instance.database;
    return await db.query('aliyun_default_voices', orderBy: 'id');
  }

  // 根据ID获取单个阿里云默认音色
  Future<Map<String, dynamic>?> getAliyunDefaultVoiceById(String id) async {
    final db = await instance.database;
    final results = await db.query(
      'aliyun_default_voices',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ==================== 主题表操作 ====================

  Future<List<Map<String, dynamic>>> getAllThemes() async {
    final db = await instance.database;
    return await db.query('themes', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getActiveTheme() async {
    final db = await instance.database;
    final results = await db.query(
      'themes',
      where: 'is_active = ?',
      whereArgs: [1],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> createTheme(Map<String, dynamic> theme) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    return await db.insert('themes', {...theme, 'created_at': now});
  }

  Future<int> updateTheme(int id, Map<String, dynamic> theme) async {
    final db = await instance.database;
    return await db.update('themes', theme, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setActiveTheme(int id) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.update('themes', {'is_active': 0});
      await txn.update(
        'themes',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> deleteTheme(int id) async {
    final db = await instance.database;
    await db.delete('themes', where: 'id = ?', whereArgs: [id]);
  }

  // 关闭数据库
  Future close() async {
    final db = await instance.database;
    await db.close();
    _database = null;
  }
}
