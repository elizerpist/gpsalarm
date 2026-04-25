import 'package:flutter/material.dart';
import 'clipboard_helper.dart';

class DebugConsole {
  DebugConsole._();

  static const _maxEntries = 500;
  static final _list = <String>[];
  static final ValueNotifier<int> _version = ValueNotifier(0);

  static void log(String message) {
    final now = DateTime.now();
    final h  = now.hour.toString().padLeft(2, '0');
    final m  = now.minute.toString().padLeft(2, '0');
    final s  = now.second.toString().padLeft(2, '0');
    final ms = (now.millisecond ~/ 10).toString().padLeft(2, '0');
    if (_list.length >= _maxEntries) _list.removeAt(0);
    _list.add('[$h:$m:$s.$ms] $message');
    _version.value++;
  }

  static void clear() {
    _list.clear();
    _version.value++;
  }

  static List<String> get entries => _list;
  static String get allText => _list.join('\n');
  static ValueNotifier<int> get notifier => _version;
}

class DebugConsoleDialog extends StatefulWidget {
  const DebugConsoleDialog({super.key});

  @override
  State<DebugConsoleDialog> createState() => _DebugConsoleDialogState();
}

class _DebugConsoleDialogState extends State<DebugConsoleDialog> {
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _textCtrl.text = DebugConsole.allText;
    DebugConsole.notifier.addListener(_onNewLog);
  }

  @override
  void dispose() {
    DebugConsole.notifier.removeListener(_onNewLog);
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onNewLog() {
    if (!mounted) return;
    final text = DebugConsole.allText;
    _textCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {});
  }

  Future<void> _copyAll() async {
    final text = _textCtrl.text;
    if (text.isEmpty) return;
    try {
      final ok = await copyToClipboard(text);
      if (!mounted) return;
      if (ok) {
        setState(() => _copied = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _copied = false);
        });
      }
    } catch (e) {
      DebugConsole.log('Clipboard failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = DebugConsole.entries.length;
    final empty = count == 0;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 40),
      child: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(children: [
                const Icon(Icons.terminal, size: 16, color: Color(0xFF2ECDC4)),
                const SizedBox(width: 8),
                const Text(
                  'Debug Console',
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: Color(0xFFCDD6F4),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '($count)',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6C7086)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: empty ? null : _copyAll,
                  icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 16),
                  color: _copied ? const Color(0xFF2ECC71) : const Color(0xFF89B4FA),
                  tooltip: _copied ? 'Copied!' : 'Copy all',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  onPressed: empty ? null : () {
                    DebugConsole.clear();
                    _textCtrl.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: const Color(0xFFF38BA8),
                  tooltip: 'Clear',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 16),
                  color: const Color(0xFF6C7086),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ]),
            ),
            const Divider(height: 1, color: Color(0xFF313244)),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.60,
                minHeight: 80,
              ),
              child: empty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No logs yet.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF6C7086)),
                        ),
                      ),
                    )
                  : TextField(
                      controller: _textCtrl,
                      focusNode: _focusNode,
                      readOnly: true,
                      maxLines: null,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        height: 1.55,
                        color: Color(0xFFCDD6F4),
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 14),
                        isDense: true,
                      ),
                      cursorColor: const Color(0xFF2ECDC4),
                      contextMenuBuilder: (ctx, editableTextState) =>
                          AdaptiveTextSelectionToolbar.editableText(
                            editableTextState: editableTextState,
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
