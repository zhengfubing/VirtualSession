import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../database/database_helper.dart';
import 'log_service.dart';

class TtsService {
  static final TtsService instance = TtsService._internal();
  TtsService._internal();

  static const _sampleRate = 24000;
  static const _bitsPerSample = 16;
  static const _channels = 1;

  static void _log(String level, String msg) {
    switch (level) {
      case 'ERROR':
        LogService.instance.error(msg);
        break;
      case 'WARN':
        LogService.instance.warn(msg);
        break;
      default:
        LogService.instance.info(msg);
    }
  }

  Future<Map<String, String>> _loadConfig() async {
    final db = DatabaseHelper.instance;
    return {
      'api_key': await db.getTtsConfig('tts_api_key') ?? '',
      'base_url':
          await db.getTtsConfig('tts_base_url') ??
          'https://dashscope.aliyuncs.com/api/v1',
      'model': await db.getTtsConfig('tts_model') ?? 'qwen3-tts-flash',
      'voice': await db.getTtsConfig('tts_voice') ?? 'Cherry',
      'language': await db.getTtsConfig('tts_language') ?? 'Chinese',
      'instructions': await db.getTtsConfig('tts_instructions') ?? '',
    };
  }

  String _cleanForTts(String text) {
    var s = text.replaceAll(RegExp(r'[（\(][^）\)]*[）\)]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  Uint8List _buildWavHeader(int dataSize) {
    final byteRate = _sampleRate * _channels * _bitsPerSample ~/ 8;
    final blockAlign = _channels * _bitsPerSample ~/ 8;
    final header = BytesBuilder();

    header.add(utf8.encode('RIFF'));
    header.add(_int32Le(36 + dataSize));
    header.add(utf8.encode('WAVE'));
    header.add(utf8.encode('fmt '));
    header.add(_int32Le(16));
    header.add(_int16Le(1));
    header.add(_int16Le(_channels));
    header.add(_int32Le(_sampleRate));
    header.add(_int32Le(byteRate));
    header.add(_int16Le(blockAlign));
    header.add(_int16Le(_bitsPerSample));
    header.add(utf8.encode('data'));
    header.add(_int32Le(dataSize));

    return header.toBytes();
  }

  Uint8List _int32Le(int value) {
    return Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  }

  Uint8List _int16Le(int value) {
    return Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);
  }

  // ==================== HTTP SSE 流式合成 ====================

  Future<List<int>> synthesize({required String text}) async {
    final config = await _loadConfig();
    return _synthesizeSse(
      text: text,
      apiKey: config['api_key']!,
      baseUrl: config['base_url']!,
      model: config['model']!,
      voice: config['voice']!,
      language: config['language']!,
      instructions: config['instructions']!,
    );
  }

  Future<List<int>> _synthesizeSse({
    required String text,
    required String apiKey,
    required String baseUrl,
    required String model,
    required String voice,
    required String language,
    String instructions = '',
  }) async {
    final cleaned = _cleanForTts(text);
    if (cleaned.isEmpty) {
      _log('ERROR', 'TTS: 文本为空');
      throw Exception('TTS 合成失败: 文本为空');
    }

    if (apiKey.isEmpty) {
      _log('ERROR', 'TTS: 未配置 API Key');
      throw Exception('TTS 合成失败: 未配置 TTS API Key，请在设置中配置');
    }

    final url = '$baseUrl/services/aigc/multimodal-generation/generation';

    final reqBody = <String, dynamic>{
      'model': model,
      'input': {'text': cleaned},
      'parameters': {
        'voice': voice,
        'language_type': language,
        'format': 'wav',
        'stream': true,
      },
    };

    if (instructions.isNotEmpty) {
      reqBody['parameters']['instructions'] = instructions;
      reqBody['parameters']['optimize_instructions'] = true;
    }

    final body = jsonEncode(reqBody);

    _log(
      'INFO',
      'TTS HTTP: model=$model voice=$voice language=$language text_len=${cleaned.length}',
    );

    final request = await HttpClient().postUrl(Uri.parse(url));
    request.headers.set('Authorization', 'Bearer $apiKey');
    request.headers.set('Content-Type', 'application/json');
    request.add(utf8.encode(body));

    final response = await request.close();

    _log('INFO', 'TTS HTTP: status=${response.statusCode}');

    final rawBytes = await response.fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );

    if (response.statusCode != 200) {
      final responseBody = utf8.decode(rawBytes, allowMalformed: true);
      _log('ERROR', 'TTS HTTP ${response.statusCode}: $responseBody');
      throw Exception(
        'TTS HTTP 请求失败\n'
        '  状态码: ${response.statusCode}\n'
        '  URL: $url\n'
        '  model: $model\n'
        '  voice: $voice\n'
        '  language: $language\n'
        '  响应: $responseBody',
      );
    }

    if (rawBytes.isEmpty) {
      _log('ERROR', 'TTS HTTP: 响应体为空');
      throw Exception('TTS HTTP 响应体为空, status=${response.statusCode}');
    }

    final bodyText = utf8.decode(rawBytes, allowMalformed: true);
    _log(
      'INFO',
      'TTS HTTP: body_len=${rawBytes.length} preview=${bodyText.length > 200 ? '${bodyText.substring(0, 200)}...' : bodyText}',
    );

    Map<String, dynamic> bodyJson;
    try {
      bodyJson = jsonDecode(bodyText) as Map<String, dynamic>;
    } catch (_) {
      bodyJson = {};
    }

    final audio = bodyJson['output']?['audio'] as Map<String, dynamic>?;

    if (audio != null) {
      final inlineData = audio['data'] as String?;
      if (inlineData != null && inlineData.isNotEmpty) {
        return _buildWavBytes([base64Decode(inlineData)]);
      }

      final ossUrl = audio['url'] as String?;
      if (ossUrl != null && ossUrl.isNotEmpty) {
        _log('INFO', 'TTS HTTP: OSS url=$ossUrl');
        return await _downloadWav(ossUrl);
      }
    }

    final audioChunks = <Uint8List>[];
    for (final line in bodyText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('data:')) {
        final data = trimmed.substring(5).trim();
        if (data == '[DONE]') break;

        try {
          final event = jsonDecode(data) as Map<String, dynamic>;
          final output = event['output'];
          if (output != null) {
            final chunkAudio = output['audio'];
            if (chunkAudio != null && chunkAudio['data'] != null) {
              audioChunks.add(base64Decode(chunkAudio['data'] as String));
            }
          }
        } catch (e) {
          _log('WARN', 'TTS HTTP: parse error line=$trimmed err=$e');
        }
      }
    }

    if (audioChunks.isEmpty) {
      _log('ERROR', 'TTS HTTP: 未收到音频数据, body_len=${rawBytes.length}');
      throw Exception(
        'TTS HTTP 未收到音频数据\n'
        '  model: $model\n'
        '  voice: $voice\n'
        '  language: $language\n'
        '  status: ${response.statusCode}\n'
        '  body_len: ${rawBytes.length}\n'
        '  body: ${bodyText.length > 500 ? '${bodyText.substring(0, 500)}...' : bodyText}',
      );
    }

    return _buildWavBytes(audioChunks);
  }

  List<int> _buildWavBytes(List<Uint8List> audioChunks) {
    final totalPcmSize = audioChunks.fold<int>(0, (sum, c) => sum + c.length);
    final wavHeader = _buildWavHeader(totalPcmSize);
    final builder = BytesBuilder();
    builder.add(wavHeader);
    for (final chunk in audioChunks) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  Future<List<int>> _downloadWav(String url) async {
    final request = await HttpClient().getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode != 200) {
      throw Exception('OSS 下载失败: ${response.statusCode}');
    }

    return response.fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );
  }

  // ==================== 按角色合成（入口方法） ====================

  Future<List<int>> synthesizeByRole({
    required String roleName,
    required String text,
  }) async {
    final db = DatabaseHelper.instance;
    final voiceConfig = await db.getVoiceByName(roleName);

    String voice;
    if (voiceConfig != null && (voiceConfig['voice_name'] as String).isNotEmpty) {
      voice = voiceConfig['voice_name'] as String;
    } else {
      final config = await _loadConfig();
      voice = config['voice']!;
    }

    final config = await _loadConfig();
    return _synthesizeSse(
      text: text,
      apiKey: config['api_key']!,
      baseUrl: config['base_url']!,
      model: config['model']!,
      voice: voice,
      language: config['language']!,
      instructions: config['instructions']!,
    );
  }
}
