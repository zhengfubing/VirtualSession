import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/file_storage_service.dart';
import '../theme/app_colors.dart';

class SoloMemoryEditPage extends StatefulWidget {
  final String memoryId;

  const SoloMemoryEditPage({super.key, required this.memoryId});

  @override
  State<SoloMemoryEditPage> createState() => _SoloMemoryEditPageState();
}

class _SoloMemoryEditPageState extends State<SoloMemoryEditPage> {
  final _fileStorage = FileStorageService();
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;
  bool _hasUnsavedChanges = false;
  bool _isLoading = true;
  String _originalContent = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(_onTextChanged);
    _loadContent();
  }

  void _onTextChanged() {
    final changed = _controller.text != _originalContent;
    if (changed != _hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = changed);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    setState(() => _isLoading = true);
    final content = await _fileStorage.readMemory(widget.memoryId);
    _originalContent = content ?? '';
    _controller.text = _originalContent;
    if (mounted) setState(() => _isLoading = false);
  }

  void _toggleMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (_isEditing) {
        _focusNode.requestFocus();
      } else {
        _focusNode.unfocus();
      }
    });
  }

  void _insertAtCursor(String prefix, {String suffix = ''}) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start;
    final end = selection.end;

    if (start < 0 || end < 0 || start > text.length) {
      _controller.text = '$text$prefix$suffix';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length - suffix.length,
      );
      return;
    }

    final selectedText = text.substring(start, end);
    final newText = StringBuffer();
    newText.write(text.substring(0, start));
    newText.write(prefix);
    newText.write(selectedText);
    newText.write(suffix);
    newText.write(text.substring(end));

    _controller.text = newText.toString();
    if (selectedText.isEmpty) {
      _controller.selection = TextSelection.collapsed(
        offset: start + prefix.length,
      );
    } else {
      _controller.selection = TextSelection(
        baseOffset: start + prefix.length,
        extentOffset: start + prefix.length + selectedText.length,
      );
    }
    _focusNode.requestFocus();
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('是否保存当前更改？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('放弃'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == 'save') {
      await _saveContent();
      return true;
    }
    return result == 'discard';
  }

  Future<void> _saveContent() async {
    final content = _controller.text;
    await _fileStorage.saveMemory(widget.memoryId, content);
    _originalContent = content;
    setState(() => _hasUnsavedChanges = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('记忆已保存')),
      );
    }
  }

  Future<void> _share() async {
    final content = _controller.text;
    if (content.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('内容为空，无法分享')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${widget.memoryId}.md');
    await file.writeAsString(content);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: widget.memoryId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: ThemedScaffold(
        appBar: AppBar(
          backgroundColor: AppColors.appBarBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: AppColors.accent),
          title: Text(
            widget.memoryId,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(
                _isEditing ? Icons.visibility_outlined : Icons.edit_outlined,
                color: AppColors.accent,
              ),
              onPressed: _toggleMode,
              tooltip: _isEditing ? '预览' : '编辑',
            ),
            IconButton(
              icon: Icon(Icons.save_outlined, color: AppColors.accent),
              onPressed: _hasUnsavedChanges ? _saveContent : null,
              tooltip: '保存',
            ),
            IconButton(
              icon: Icon(Icons.share_outlined, color: AppColors.accent),
              onPressed: _share,
              tooltip: '分享',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_isEditing) _buildToolbar(),
                  Expanded(
                    child: _isEditing ? _buildEditor() : _buildPreview(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.headerBg,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolbarButton(
              icon: Icons.format_bold,
              tooltip: '粗体',
              onPressed: () => _insertAtCursor('**', suffix: '**'),
            ),
            _ToolbarButton(
              icon: Icons.format_italic,
              tooltip: '斜体',
              onPressed: () => _insertAtCursor('*', suffix: '*'),
            ),
            _ToolbarButton(
              icon: Icons.strikethrough_s,
              tooltip: '删除线',
              onPressed: () => _insertAtCursor('~~', suffix: '~~'),
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              icon: Icons.title,
              tooltip: '一级标题',
              onPressed: () => _insertAtCursor('\n## '),
            ),
            _ToolbarButton(
              icon: Icons.text_fields,
              tooltip: '二级标题',
              onPressed: () => _insertAtCursor('\n### '),
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              icon: Icons.format_list_bulleted,
              tooltip: '无序列表',
              onPressed: () => _insertAtCursor('\n- '),
            ),
            _ToolbarButton(
              icon: Icons.format_list_numbered,
              tooltip: '有序列表',
              onPressed: () => _insertAtCursor('\n1. '),
            ),
            _ToolbarButton(
              icon: Icons.checklist,
              tooltip: '任务列表',
              onPressed: () => _insertAtCursor('\n- [ ] '),
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              icon: Icons.code,
              tooltip: '行内代码',
              onPressed: () => _insertAtCursor('`', suffix: '`'),
            ),
            _ToolbarButton(
              icon: Icons.data_object,
              tooltip: '代码块',
              onPressed: () => _insertAtCursor('\n```\n', suffix: '\n```\n'),
            ),
            _ToolbarButton(
              icon: Icons.format_quote,
              tooltip: '引用',
              onPressed: () => _insertAtCursor('\n> '),
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              icon: Icons.horizontal_rule,
              tooltip: '分割线',
              onPressed: () => _insertAtCursor('\n---\n'),
            ),
            _ToolbarButton(
              icon: Icons.link,
              tooltip: '链接',
              onPressed: () => _insertAtCursor('[', suffix: '](url)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontSize: 16, height: 1.6),
      decoration: const InputDecoration(
        hintText: '输入 Markdown 内容...',
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }

  Widget _buildPreview() {
    return Markdown(
      data: _controller.text.isEmpty ? '*暂无内容*' : _controller.text,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(fontSize: 16, height: 1.6, color: AppColors.text),
        h1: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.text),
        h2: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text),
        h3: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text),
        code: TextStyle(
          fontSize: 14,
          backgroundColor: Colors.grey.shade100,
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: AppColors.accent, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppColors.text),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.grey.shade300,
    );
  }
}
