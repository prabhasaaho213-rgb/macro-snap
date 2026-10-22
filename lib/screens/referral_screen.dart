import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../core/theme.dart';
import '../services/referral_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  String? _myCode;
  bool _loading = true;
  final _codeCtrl = TextEditingController();
  bool _applying = false;
  String? _applyResult;

  @override
  void initState() {
    super.initState();
    _loadCode();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCode() async {
    try {
      final code = await ReferralService.generateCode();
      if (mounted) {
        setState(() {
          _myCode = code;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _myCode = null;
          _loading = false;
        });
      }
    }
  }

  Future<void> _share() async {
    if (_myCode == null) return;
    await Share.share(
      'Join MacroSnap and get a FREE month! Use my referral code: $_myCode\n\nTrack every meal, know your macros. Download now!\nhttps://play.google.com/store/apps/details?id=com.macrosnap.macro_snap',
    );
  }

  Future<void> _apply() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _applying = true;
      _applyResult = null;
    });
    try {
      await ReferralService.applyCode(code);
      // The user can leave this screen while the code is being applied; a
      // bare setState after the await would then throw (red screen in debug,
      // swallowed error in release).
      if (!mounted) return;
      setState(() {
        _applyResult = 'success';
        _applying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyResult = e.toString().replaceFirst('Exception: ', '');
        _applying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Refer a Friend',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GlassCard(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: MacroSnapTheme.neonGreen,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Give a Free Month',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Share your code and both get Pro free for a month',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const CircularProgressIndicator(
                    strokeWidth: 3,
                    color: MacroSnapTheme.neonGreen,
                  )
                else if (_myCode != null)
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: (isDark
                              ? MacroSnapTheme.cardDark
                              : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: MacroSnapTheme.neonGreen.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: SelectableText(
                          _myCode!,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 6,
                            color: MacroSnapTheme.greenText(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tap code to copy, then share',
                        style: TextStyle(
                          fontSize: 12,
                          color: MacroSnapTheme.textTertiary(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: GradientButton(
                          label: 'Share on WhatsApp',
                          onPressed: _share,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Sign in to get your referral code',
                    style: TextStyle(
                      color: MacroSnapTheme.textTertiary(context),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Have a code? Enter it below',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Enter referral code',
                    filled: true,
                    fillColor: isDark
                        ? MacroSnapTheme.cardDark
                        : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 18,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GradientButton(
                label: 'Apply',
                onPressed: _applying ? null : _apply,
                width: 100,
              ),
            ],
          ),
          if (_applying)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(color: MacroSnapTheme.neonGreen),
            ),
          if (_applyResult == 'success')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GlassCard(
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: MacroSnapTheme.neonGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Free month activated!',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_applyResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GlassCard(
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: MacroSnapTheme.neonPink,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _applyResult!,
                        style: TextStyle(
                          fontSize: 13,
                          color: MacroSnapTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
