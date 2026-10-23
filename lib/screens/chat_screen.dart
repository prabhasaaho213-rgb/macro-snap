import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../services/guru_service.dart';
import 'subscription_screen.dart';

enum _Role { user, assistant }

class _ChatMessage {
  final _Role role;
  final String text;

  /// A canned system bubble (the offline notice, the Pro-gate notice) is
  /// displayed but never remembered: it is not part of the real
  /// conversation and must not be replayed to the backend as history.
  final bool persist;
  const _ChatMessage({required this.role, required this.text, this.persist = true});
}

/// In-app nutrition assistant "Guru", opened from the Home screen's floating
/// button. It answers food / nutrition / protein questions — about the user's
/// own logged day (via the snapshot [GuruService] attaches) as well as general
/// nutrition — but nothing else: the restriction is enforced by the backend's
/// system instruction, so it holds no matter how the user phrases a request.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _greeting =
      'Hi! I\u2019m Guru, your MacroSnap nutrition assistant. Ask me anything '
      'about food, calories, protein or meal ideas \u2014 for example \u201CHow '
      'much protein is in 100g of paneer?\u201D';

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _busy = false;

  /// Restored from [GuruService.loadChatHistory] on open, so a later re-open
  /// continues the last conversation instead of starting blank. Async, and
  /// set before any reply is handled (see initState/_restore).
  bool _restored = false;

  /// Set when the backend answered 403 `pro_required`. The composer is then
  /// replaced by the upgrade card — no further turn can be sent.
  bool _proRequired = false;

  @override
  void initState() {
    super.initState();
    _messages.add(const _ChatMessage(role: _Role.assistant, text: _greeting));
    unawaited(_restore());
  }

  /// Restores the last saved conversation (this account only) after the
  /// greeting. Older transcript first, so the chat scrolls like it played.
  Future<void> _restore() async {
    try {
      final saved = await GuruService.loadChatHistory();
      _restored = true; // Also true for "nothing saved": openers may show.
      if (!mounted || saved.isEmpty) return;
      setState(() {
        for (final m in saved) {
          _messages.add(
            _ChatMessage(
              role: m['role'] == 'user' ? _Role.user : _Role.assistant,
              text: m['text'] ?? '',
            ),
          );
        }
      });
      _restored = true;
      _scrollToEnd();
    } catch (_) {
      // Never block the chat over a corrupt transcript.
    }
  }

  /// The stored part of the conversation: every real turn, without the
  /// greeting and without canned system bubbles.
  List<Map<String, String>> get _transcript => [
    for (final m in _messages.skip(1))
      if (m.persist)
        {'role': m.role == _Role.user ? 'user' : 'model', 'text': m.text},
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    HapticFeedback.lightImpact();
    _input.clear();
    setState(() {
      _messages.add(_ChatMessage(role: _Role.user, text: text));
      _busy = true;
    });
    _scrollToEnd();
    try {
      // Everything before the current message is context; the opening
      // greeting is not part of the conversation. The newest turn (the
      // message the user just sent) is also dropped — it travels as
      // `message` itself.
      final transcript = _transcript;
      final history = transcript.length <= 1
          ? <Map<String, String>>[]
          : transcript.sublist(0, transcript.length - 1);
      // GuruService attaches the personalized snapshot of this user's day
      // (meals, macro totals, targets, habits, water) to the request.
      final data = await GuruService.send(message: text, history: history);
      // A non-2xx body carries `message` (the human-readable line, e.g. the 429
      // rate-limit text) and, failing that, `error` (a machine code). Prefer
      // the message so the user never reads a bare code like `rate_limited`.
      final reply = data['reply'] is String
          ? data['reply'] as String
          : (data['message']?.toString() ??
                data['error']?.toString() ??
                'Something went wrong. Please try again.');
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(role: _Role.assistant, text: reply));
          _busy = false;
        });
        // Remember this conversation so reopening Guru continues it.
        await GuruService.saveChatHistory(_transcript);
      }
    } on GuruProRequiredException catch (e) {
      // The Pro gate closed on us mid-conversation (e.g. the free plan just
      // expired). Explain it in the thread and lock the composer.
      if (mounted) {
        setState(() {
          _messages.add(
            _ChatMessage(role: _Role.assistant, text: e.message, persist: false),
          );
          _proRequired = true;
          _busy = false;
        });
      }
      _scrollToEnd();
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.add(
            _ChatMessage(
              role: _Role.assistant,
              text:
                  'I couldn\u2019t reach the server. Check your connection '
                  'and try again.',
              persist: false,
            ),
          );
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
        title: const Text('Guru'),
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
          if (_messages.length == 1 && _restored && !_proRequired && !_busy)
            _buildSuggestions(isDark),
          _proRequired ? _buildUpsellBar(isDark) : _buildInputBar(isDark),
        ],
      ),
    );
  }

  /// Shown in place of the composer once the backend has refused with
  /// 403 `pro_required`: Guru needs Pro, so point at the plans instead of
  /// letting the user type into a box that can never answer.
  Widget _buildUpsellBar(bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: isDark
              ? MacroSnapTheme.surfaceDark
              : MacroSnapTheme.surfaceLight,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : const Color(0xFFE5E5E5),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: Color(0xFF7C3AED),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Guru is a Pro feature. Upgrade to keep chatting.',
                    style: TextStyle(
                      fontSize: 13,
                      color: MacroSnapTheme.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('See plans'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Empty-state guidance: with only the greeting in the thread, offer a few
  /// tappable openers instead of leaving the user staring at a blank composer.
  Widget _buildSuggestions(bool isDark) {
    const prompts = [
      'How much protein in 100g paneer?',
      'Healthy dinner under 400 kcal?',
      'Am I hitting my protein today?',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in prompts)
            ActionChip(
              label: Text(p, style: const TextStyle(fontSize: 12)),
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              side: BorderSide(
                color: MacroSnapTheme.borderSubtle(context),
                width: 0.5,
              ),
              onPressed: () => _send(p),
            ),
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
          color: isDark
              ? MacroSnapTheme.surfaceDark
              : MacroSnapTheme.surfaceLight,
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
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
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
                icon: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 20,
                ),
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
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
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
              child: const Icon(
                Icons.smart_toy_rounded,
                color: Colors.white,
                size: 15,
              ),
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
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Colors.white,
              size: 15,
            ),
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
