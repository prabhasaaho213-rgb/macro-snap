part of 'home_screen.dart';

// Split out of home_screen.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _HomeHeader on _HomeScreenState {
  // The free-trial countdown banner was removed with the trials themselves:
  // Pro now starts at a ₹1 first month (charged up front) followed by the
  // ₹49/month Razorpay autopay the customer approves at checkout, so nothing
  // here keeps a live countdown slot on the home screen.

  // ─── HEADER ────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, bool isDark) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good Morning'
        : now.hour < 18
        ? 'Good Afternoon'
        : 'Good Evening';
    return Padding(
      // Tighter top so the greeting doesn't wander far from the content below.
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _name.isNotEmpty ? _name : 'MacroSnap',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Scans remaining badge (Habitly neon pill style). It renders the
              // one value ScanGate publishes, so it cannot flicker between a
              // stale free count and the server's "Unlimited".
              ValueListenableBuilder<int?>(
                valueListenable: ScanGate.remaining,
                builder: (context, scans, _) {
                  final count = scans;
                  final unknown = count == null;
                  final exhausted = count != null && count <= 0;
                  final accent = unknown
                      ? MacroSnapTheme.textTertiary(context)
                      : exhausted
                      ? MacroSnapTheme.neonPink
                      : MacroSnapTheme.neonGreen;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: MacroSnapTheme.neonPill(accent),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, size: 14, color: accent),
                        const SizedBox(width: 4),
                        Text(
                          unknown
                              ? '—'
                              : count >= 99
                              ? 'Unlimited'
                              : '$count',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: exhausted
                                ? MacroSnapTheme.neonPink
                                : MacroSnapTheme.greenText(context),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              ScaleOnPress(
                onTap: () => Navigator.push(
                  context,
                  habitFlowRoute(const SettingsScreen()),
                ),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? MacroSnapTheme.cardDark
                        : const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.settings_rounded,
                    size: 20,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
