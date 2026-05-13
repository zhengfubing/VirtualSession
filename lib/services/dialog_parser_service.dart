import 'dart:convert';
import '../models/chat_dialog_item.dart';
import '../models/chat_dialog_payload.dart';
import '../models/user_message_content.dart';

class StreamedReplyItem {
  final String senderName;
  final String content;
  final bool complete;
  final String status;
  final String statusType;
  final String statusContent;

  StreamedReplyItem({
    required this.senderName,
    required this.content,
    this.complete = false,
    this.status = '',
    this.statusType = '',
    this.statusContent = '',
  });
}

/// 对话消息解析服务
/// 参考 Python chat/validators.py
class DialogParserService {
  static final DialogParserService instance = DialogParserService._();
  DialogParserService._();

  /// 从 LLM 文本输出中解析对话消息列表
  /// 返回 ChatDialogItem 列表（替代旧的 DialogItem）
  List<ChatDialogItem>? parseDialogItemsFromText(String content) {
    if (content.isEmpty) return null;

    // 去除 markdown 代码围栏
    var cleaned = content.trim();
    if (cleaned.startsWith('```')) {
      final firstNewline = cleaned.indexOf('\n');
      if (firstNewline != -1) {
        cleaned = cleaned.substring(firstNewline + 1);
      }
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();

    // JSON 解析
    Map<String, dynamic> data;
    try {
      final parsed = jsonDecode(cleaned);
      if (parsed is! Map<String, dynamic>) return null;
      data = parsed;
    } catch (_) {
      return null;
    }

    final payload = ChatDialogPayload.fromJson(data);
    return payload.messages.isNotEmpty ? payload.messages : null;
  }

  /// 解析对话 payload，返回 ChatDialogPayload 对象
  ChatDialogPayload? parseDialogPayload(Map<String, dynamic> data) {
    try {
      final payload = ChatDialogPayload.fromJson(data);
      return payload.isValid ? payload : null;
    } catch (_) {
      return null;
    }
  }

  /// 构建用户消息对象（用于 API 请求）
  UserMessageContent buildUserMessageContent({
    required String senderName,
    required String userInput,
    String sceneName = '',
  }) {
    return UserMessageContent.build(
      senderName: senderName,
      messageContent: userInput,
      scene: sceneName,
    );
  }

  /// 构建用户消息 JSON 字符串（用于 context storage）
  /// 兼容旧接口
  String buildUserMessageJson({
    required String senderName,
    required String userInput,
    String sceneName = '',
  }) {
    return buildUserMessageContent(
      senderName: senderName,
      userInput: userInput,
      sceneName: sceneName,
    ).toJsonString();
  }

  /// 构建用户消息 Map（用于 API 请求）
  /// 兼容旧接口
  Map<String, dynamic> buildUserMessageMap({
    required String senderName,
    required String userInput,
    String sceneName = '',
  }) {
    return buildUserMessageContent(
      senderName: senderName,
      userInput: userInput,
      sceneName: sceneName,
    ).toJson();
  }

  /// 构建助手消息 Map（用于 API 请求）
  /// 兼容旧接口
  Map<String, dynamic> buildAssistantMessageMap(String content) {
    return {
      'sender_name': '',
      'status': <String>[],
      'status_type': '',
      'status_content': '',
      'scene': '',
      'message_content': content,
    };
  }

  /// 构建助手消息 JSON 字符串（用于 context storage）
  /// 兼容旧接口
  String buildAssistantMessageJson(String content) {
    return jsonEncode(buildAssistantMessageMap(content));
  }

  /// 从流式原始文本中渐进式解析消息项
  /// 参考 Vue ChatView.vue parseStreamedReplyItems
  List<StreamedReplyItem> parseStreamedReplyItems(String rawText) {
    if (rawText.isEmpty) return [];
    final clean = _stripJsonFence(rawText);

    final senderCandidates = <String>[];
    final senderRegex = RegExp(r'"sender_name"\s*:\s*"((?:\\.|[^"\\])*)"');
    for (final match in senderRegex.allMatches(clean)) {
      senderCandidates.add(_decodeJsonFragment(match.group(1) ?? '', true));
    }

    final statusCandidates = <String>[];
    final statusRegex = RegExp(r'"status"\s*:\s*\[(.*?)\]');
    for (final match in statusRegex.allMatches(clean)) {
      statusCandidates.add(_decodeJsonFragment(match.group(1) ?? '', true));
    }

    final statusTypeCandidates = <String>[];
    final statusTypeRegex = RegExp(r'"status_type"\s*:\s*"((?:\\.|[^"\\])*)"');
    for (final match in statusTypeRegex.allMatches(clean)) {
      statusTypeCandidates.add(_decodeJsonFragment(match.group(1) ?? '', true));
    }

    final statusContentCandidates = <String>[];
    final statusContentRegex = RegExp(
      r'"status_content"\s*:\s*"((?:\\.|[^"\\])*)"',
    );
    for (final match in statusContentRegex.allMatches(clean)) {
      statusContentCandidates.add(
        _decodeJsonFragment(match.group(1) ?? '', true),
      );
    }

    final nameList = _parseNamesFromRaw(clean);

    final items = <StreamedReplyItem>[];
    final contentRegex = RegExp(r'"message_content"\s*:\s*"');
    for (final match in contentRegex.allMatches(clean)) {
      final startPos = match.end;
      final quoted = _extractQuotedValue(clean, startPos);
      items.add(
        StreamedReplyItem(
          senderName: senderCandidates.length > items.length
              ? senderCandidates[items.length]
              : (nameList.length > items.length ? nameList[items.length] : ''),
          content: _decodeJsonFragment(quoted.$2, quoted.$1),
          complete: quoted.$1,
          status: statusCandidates.length > items.length
              ? statusCandidates[items.length]
              : '',
          statusType: statusTypeCandidates.length > items.length
              ? statusTypeCandidates[items.length]
              : '',
          statusContent: statusContentCandidates.length > items.length
              ? statusContentCandidates[items.length]
              : '',
        ),
      );
    }
    return items;
  }

  /// 解析 sender_names 列表
  List<String> _parseNamesFromRaw(String rawText) {
    final names = <String>[];
    final clean = _stripJsonFence(rawText);
    final nameListMatch = RegExp(
      r'"sender_names"\s*:\s*\[([\s\S]*?)\]',
    ).firstMatch(clean);
    if (nameListMatch == null) return names;
    final itemRegex = RegExp(r'"((?:\\.|[^"\\])*)"');
    for (final match in itemRegex.allMatches(nameListMatch.group(1) ?? '')) {
      names.add(_decodeJsonFragment(match.group(1) ?? '', true));
    }
    return names;
  }

  /// 解析 sender_count
  int parseReplyTotalFromRaw(String rawText, int itemCount, int nameCount) {
    final clean = _stripJsonFence(rawText);
    final countMatch = RegExp(r'"sender_count"\s*:\s*(\d+)').firstMatch(clean);
    final declared = countMatch != null
        ? int.tryParse(countMatch.group(1) ?? '0') ?? 0
        : 0;
    return [declared, itemCount, nameCount].reduce((a, b) => a > b ? a : b);
  }

  /// 从引号字符串中提取值（处理转义）
  (bool, String) _extractQuotedValue(String source, int startPos) {
    var i = startPos;
    var escaped = false;
    while (i < source.length) {
      final ch = source[i];
      if (escaped) {
        escaped = false;
        i++;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        i++;
        continue;
      }
      if (ch == '"') {
        return (true, source.substring(startPos, i));
      }
      i++;
    }
    return (false, source.substring(startPos));
  }

  String _stripJsonFence(String text) {
    var clean = text.replaceFirst(
      RegExp(r'^\s*```json\s*', caseSensitive: false),
      '',
    );
    if (clean.endsWith('```')) {
      clean = clean.substring(0, clean.length - 3);
    }
    return clean;
  }

  String _decodeJsonFragment(String fragment, bool complete) {
    if (fragment.isEmpty) return '';
    if (complete) {
      try {
        final decoded = jsonDecode('"$fragment"');
        if (decoded is String) return decoded;
      } catch (_) {}
    }
    return fragment
        .replaceAll('\\\\', '\\')
        .replaceAll('\\"', '"')
        .replaceAll('\\n', '\n')
        .replaceAll('\\r', '\r')
        .replaceAll('\\t', '\t');
  }
}

/// 兼容旧代码：DialogItem 别名
@Deprecated('使用 ChatDialogItem 替代')
typedef DialogItem = ChatDialogItem;
