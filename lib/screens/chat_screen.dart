import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/theme.dart';
import '../services/gemini_service.dart';

enum _Role { user, assistant }

class _ChatMessage {
  final _Role role;
  final String text;
  const _ChatMessage({required this.role, required this.text});
}

/// In-app nutrition assistant, opened from the Home screen's floating
/// button. It only answers food / nutrition / protein questions — the
/// restriction is enforced by the backend's system instruction, so it holds
/// no matter how the user phrases a request.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _greeting =
      'Hi! I\u2019m the MacroSnap nutrition assistant. Ask me anything about '
      'food, calories, protein or meal ideas \u2014 for example \u201CHow much '
      'protein is in 100g of paneer?\u201D';

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _messages.add(const _ChatMessage(role: _Role.assistant, text: _greeting));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _messages.add(_ChatMessage(role: _Role.user, text: text));
      _busy = true;
    });
    _scrollToEnd();
    try {
      // Everything before the current message is context; the opening
      // greeting is not part of the conversation.
      final history = [
        for (final m in _messages.take(_messages.length - 1))
          {'role': m.role == _Role.user ? 'user' : 'model', 'text': m.text},
      ];
      final resp = await http
          .post(
            Uri.parse('${GeminiService.serverUrl}/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': text, 'history': history}),
          )
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final reply = resp.statusCode == 200 && data['reply'] is String
          ? data['reply'] as String
          : (data['error']?.toString() ??
              'Something went wrong. Please try again.');
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(role: _Role.assistant, text: reply));
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.add(const _ChatMessage(
            role: _Role.assistant,
            text: 'I couldn\u2019t reach the server. Check your connection '
                'and try again.',
          ));
          _busy = false;
        });
      }
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 140,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Nutrition Assistant'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _messages.length + (_busy ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _messages.length) return const _TypingBubble();
                return _ChatBubble(message: _messages[i]);
              },
            ),
          ),
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: isDark ? MacroSnapTheme.surfaceDark : MacroSnapTheme.surfaceLight,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : const Color(0xFFE5E5E5),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !_busy,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                maxLength: 2000,
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Ask about food, calories or protein...',
                  hintStyle: TextStyle(
                    color: MacroSnapTheme.textTertiary(context),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF3F0FF),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                ),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _busy ? null : () => _send(_input.text),
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _Role.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 15),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: isUser
                    ? const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                      )
                    : null,
                color: isUser
                    ? null
                    : (isDark ? Colors.white10 : const Color(0xFFF3F0FF)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: isUser
                      ? Colors.white
                      : (isDark ? Colors.white : const Color(0xFF1A1A1A)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 15),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF3F0FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const SizedBox(
              width: 34,
              height: 10,
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: Color(0xFF7C3AED),
                minHeight: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
