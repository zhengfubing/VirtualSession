import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../database/database_helper.dart';
import '../services/tts_service.dart';
import '../theme/app_colors.dart';

class TtsTestPage extends StatefulWidget {
  const TtsTestPage({super.key});

  @override
  State<TtsTestPage> createState() => _TtsTestPageState();
}

class _TtsTestPageState extends State<TtsTestPage> {
  final _textController = TextEditingController(text: '你好，这是一个语音合成测试。');
  final _db = DatabaseHelper.instance;
  final _audioPlayer = AudioPlayer();

  List<Map<String, dynamic>> _roles = [];
  String? _selectedRole;
  String _voiceName = '';
  bool _isLoadingRoles = true;
  bool _isSynthesizing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  @override
  void dispose() {
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    final roles = await _db.query(
      'prompts',
      where: 'prompt_type = ?',
      whereArgs: ['roleSettingPrompt'],
    );
    setState(() {
      _roles = roles;
      _isLoadingRoles = false;
      if (roles.isNotEmpty) {
        _selectedRole = roles.first['file_name'] as String;
        _loadVoiceName(_selectedRole!);
      }
    });
  }

  Future<void> _loadVoiceName(String roleName) async {
    final config = await _db.getVoiceByName(roleName);
    setState(() {
      _voiceName = config?['voice_name'] as String? ?? '';
    });
  }

  Future<void> _onRoleChanged(String? roleName) async {
    if (roleName == null) return;
    setState(() {
      _selectedRole = roleName;
      _voiceName = '';
    });
    await _loadVoiceName(roleName);
  }

  Future<void> _synthesizeAndPlay() async {
    if (_selectedRole == null) {
      setState(() => _statusMessage = '请先选择角色');
      return;
    }

    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _statusMessage = '请输入文本');
      return;
    }

    setState(() {
      _isSynthesizing = true;
      _statusMessage = '正在合成语音...';
    });

    try {
      final audioBytes = await TtsService.instance.synthesizeByRole(
        roleName: _selectedRole!,
        text: text,
      );

      setState(() => _statusMessage = '合成完成，正在播放...');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_playback.wav');
      await file.writeAsBytes(audioBytes);
      await _audioPlayer.play(DeviceFileSource(file.path));

      setState(() {
        _statusMessage = '正在播放 (${audioBytes.length} 字节)';
        _isSynthesizing = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = '合成失败: $e';
        _isSynthesizing = false;
      });
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
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text(
          'TTS 测试',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择角色',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              '选择角色后使用该角色配置的音色进行合成',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            _isLoadingRoles
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: _roles.map((r) {
                      final name = r['file_name'] as String;
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: _onRoleChanged,
                  ),
            if (_selectedRole != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _voiceName.isNotEmpty
                      ? AppColors.accent.withAlpha(25)
                      : Colors.grey.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _voiceName.isNotEmpty
                        ? AppColors.accent.withAlpha(80)
                        : Colors.grey.withAlpha(80),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.record_voice_over,
                      color: _voiceName.isNotEmpty ? AppColors.accent : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _voiceName.isNotEmpty
                            ? '音色: $_voiceName'
                            : '未配置音色，将使用默认音色',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _voiceName.isNotEmpty ? AppColors.text : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              '输入文本',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '请输入要合成的文本',
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSynthesizing ? null : _synthesizeAndPlay,
                icon: _isSynthesizing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.volume_up),
                label: Text(_isSynthesizing ? '合成中...' : '合成并播放'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_statusMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
