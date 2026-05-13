import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/ai_model.dart';

class AIStreamEvent {
  final String? reasoningContent;
  final String? content;
  final Map<String, dynamic>? usage;

  AIStreamEvent({this.reasoningContent, this.content, this.usage});
}

class AICompletionResult {
  final String reasoning;
  final String answer;
  final Map<String, dynamic>? usage;
  final String model;
  final int latencyMs;

  AICompletionResult({
    this.reasoning = '',
    this.answer = '',
    this.usage,
    this.model = '',
    this.latencyMs = 0,
  });
}

class AIService {
  /// 将 JSON 字符串消息列表解析为 Map 列表
  /// 输入: ['{"role":"user","content":"..."}', ...]
  /// 输出: [{'role': 'user', 'content': '...'}, ...]
  static List<Map<String, dynamic>> _parseJsonMessages(List<String> messages) {
    return messages.map((jsonStr) {
      try {
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (e) {
        // 如果解析失败，返回一个默认的错误消息
        return {'role': 'user', 'content': jsonStr};
      }
    }).toList();
  }

  /// 构建请求体
  /// messages 是 JSON 字符串列表
  static String _buildRequestBody({
    required String model,
    required List<String> messages,
    required bool stream,
    String? systemPrompt,
    Map<String, dynamic>? extraBody,
    List<Map<String, dynamic>>? tools,
  }) {
    final allMessages = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      allMessages.add({'role': 'system', 'content': systemPrompt});
    }
    allMessages.addAll(_parseJsonMessages(messages));

    final body = <String, dynamic>{
      'model': model,
      'messages': allMessages,
      'stream': stream,
    };
    if (stream) {
      body['stream_options'] = {'include_usage': true};
    }
    if (extraBody != null && extraBody.isNotEmpty) {
      body.addAll(extraBody);
    }

    // 合并内置搜索工具和自定义工具
    final allTools = <Map<String, dynamic>>[];
    if (extraBody?['enable_search'] == true) {
      allTools.add({
        'type': 'builtin_function',
        'function': {'name': 'web_search'},
      });
    }
    if (tools != null && tools.isNotEmpty) {
      allTools.addAll(tools);
    }
    if (allTools.isNotEmpty) {
      body['tools'] = allTools;
    }

    return jsonEncode(body);
  }

  /// 流式聊天完成
  /// messages: JSON 字符串列表，每个元素格式: '{"role":"user","content":"..."}'
  static Stream<AIStreamEvent> streamChatCompletion({
    required AIModel model,
    required List<String> messages,
    String? systemPrompt,
    Map<String, dynamic>? extraBody,
    List<Map<String, dynamic>>? tools,
  }) async* {
    final uri = Uri.parse('${model.baseUrl}/chat/completions');

    final requestBody = _buildRequestBody(
      model: model.name,
      messages: messages,
      stream: true,
      systemPrompt: systemPrompt,
      extraBody: extraBody,
      tools: tools,
    );

    // DEBUG: 打印请求体
    print('=== AI Service Request Body ===');
    print(requestBody);
    print('================================');

    final request = await HttpClient().postUrl(uri);
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.headers.set('Authorization', 'Bearer ${model.apiKey}');
    request.write(requestBody);

    final response = await request.close();
    if (response.statusCode != 200) {
      final err = await response.transform(utf8.decoder).join();
      throw Exception('HTTP ${response.statusCode}: $err');
    }

    await for (final chunk in response.transform(utf8.decoder)) {
      final lines = chunk.split('\n');
      for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') return;
        if (data.isEmpty) continue;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List<dynamic>?;
          Map<String, dynamic>? usage;
          if (json.containsKey('usage') && json['usage'] != null) {
            usage = json['usage'] as Map<String, dynamic>;
          }

          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta != null) {
              final reasoning = delta['reasoning_content'] as String?;
              final content = delta['content'] as String?;

              if ((reasoning != null && reasoning.isNotEmpty) ||
                  (content != null && content.isNotEmpty) ||
                  usage != null) {
                yield AIStreamEvent(
                  reasoningContent: reasoning,
                  content: content,
                  usage: usage,
                );
              }
            }
          }

          if (usage != null && (choices == null || choices.isEmpty)) {
            yield AIStreamEvent(usage: usage);
          }
        } catch (_) {}
      }
    }
  }

  /// 非流式聊天完成
  /// messages: JSON 字符串列表，每个元素格式: '{"role":"user","content":"..."}'
  static Future<AICompletionResult> chatCompletion({
    required AIModel model,
    required List<String> messages,
    String? systemPrompt,
    Map<String, dynamic>? extraBody,
    List<Map<String, dynamic>>? tools,
  }) async {
    final uri = Uri.parse('${model.baseUrl}/chat/completions');
    final stopwatch = Stopwatch()..start();

    final requestBody = _buildRequestBody(
      model: model.name,
      messages: messages,
      stream: false,
      systemPrompt: systemPrompt,
      extraBody: extraBody,
      tools: tools,
    );

    final request = await HttpClient().postUrl(uri);
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.headers.set('Authorization', 'Bearer ${model.apiKey}');
    request.write(requestBody);

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    stopwatch.stop();

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $responseBody');
    }

    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    final choice = (json['choices'] as List).first;
    final message = choice['message'] as Map<String, dynamic>;

    Map<String, dynamic>? usage;
    if (json['usage'] != null) {
      usage = json['usage'] as Map<String, dynamic>;
    }

    return AICompletionResult(
      reasoning: message['reasoning_content'] as String? ?? '',
      answer: message['content'] as String? ?? '',
      usage: usage,
      model: json['model'] as String? ?? model.name,
      latencyMs: stopwatch.elapsedMilliseconds,
    );
  }
}
