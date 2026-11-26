import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/theme.dart';

/// One illustrated profile picture in the app's avatar set.
///
/// The art ships as the supplied 512 px transparent PNGs under
/// `assets/images/avatars/`, one per avatar, rather than being drawn in code:
/// these are full illustrations with faces, hair and lighting, which a
/// CustomPainter could not reproduce faithfully. The files keep the pack's own
/// numbered names, and [SnapAvatarStyle.asset] points at them, so replacing the
/// pack later is a file swap.
class SnapAvatarStyle {
  const SnapAvatarStyle({
    required this.id,
    required this.label,
    required this.asset,
  });

  /// Stable id stored on the profile (`art:panda`). Never rename one: it is
  /// persisted on the device, synced with the diet profile, and written into
  /// the leaderboard and league rows other people read.
  final String id;

  /// Spoken by a screen reader in the picker.
  final String label;

  /// Bundled image for this avatar.
  final String asset;
}

/// The avatar set, in picker order (the order of the approved sheet).
class SnapAvatars {
  const SnapAvatars._();

  /// Prefix that separates an illustrated avatar from a legacy emoji.
  ///
  /// Profiles saved before this existed hold an emoji (`😎`), and the app has
  /// to keep rendering those instead of showing a blank disc.
  static const String prefix = 'art:';

  static const List<SnapAvatarStyle> all = [
    SnapAvatarStyle(
      id: 'cool-guy',
      label: 'Cool guy',
      asset: 'assets/images/avatars/01_cool_guy.png',
    ),
    SnapAvatarStyle(
      id: 'headphones-girl',
      label: 'Headphones girl',
      asset: 'assets/images/avatars/02_headphones_girl.png',
    ),
    SnapAvatarStyle(
      id: 'pixel-guy',
      label: 'Pixel guy',
      asset: 'assets/images/avatars/03_pixel_guy.png',
    ),
    SnapAvatarStyle(
      id: 'astronaut',
      label: 'Astronaut',
      asset: 'assets/images/avatars/04_astronaut.png',
    ),
    SnapAvatarStyle(
      id: 'cap-guy',
      label: 'Cap guy',
      asset: 'assets/images/avatars/05_cap_guy.png',
    ),
    SnapAvatarStyle(
      id: 'masked-guy',
      label: 'Masked guy',
      asset: 'assets/images/avatars/06_masked_guy.png',
    ),
    SnapAvatarStyle(
      id: 'glasses-girl',
      label: 'Glasses girl',
      asset: 'assets/images/avatars/07_glasses_girl.png',
    ),
    SnapAvatarStyle(
      id: 'bearded-guy',
      label: 'Bearded guy',
      asset: 'assets/images/avatars/08_bearded_guy.png',
    ),
    SnapAvatarStyle(
      id: 'purple-hoodie',
      label: 'Purple hoodie',
      asset: 'assets/images/avatars/09_purple_hoodie.png',
    ),
    SnapAvatarStyle(
      id: 'cap-girl',
      label: 'Cap girl',
      asset: 'assets/images/avatars/10_cap_girl.png',
    ),
    SnapAvatarStyle(
      id: 'panda',
      label: 'Panda',
      asset: 'assets/images/avatars/11_panda.png',
    ),
    SnapAvatarStyle(
      id: 'book-reader',
      label: 'Book reader',
      asset: 'assets/images/avatars/12_book_reader.png',
    ),
    SnapAvatarStyle(
      id: 'music-fan',
      label: 'Music fan',
      asset: 'assets/images/avatars/13_music_fan.png',
    ),
    SnapAvatarStyle(
      id: 'mystery-hood',
      label: 'Mystery hood',
      asset: 'assets/images/avatars/14_mystery_hood.png',
    ),
    SnapAvatarStyle(
      id: 'peace-girl',
      label: 'Peace girl',
      asset: 'assets/images/avatars/15_peace_girl.png',
    ),
    SnapAvatarStyle(
      id: 'sunglasses-guy',
      label: 'Sunglasses guy',
      asset: 'assets/images/avatars/16_sunglasses_guy.png',
    ),
    SnapAvatarStyle(
      id: 'dj',
      label: 'DJ',
      asset: 'assets/images/avatars/17_dj.png',
    ),
    SnapAvatarStyle(
      id: 'mountain-view',
      label: 'Mountain view',
      asset: 'assets/images/avatars/18_mountain_view.png',
    ),
    SnapAvatarStyle(
      id: 'bubblegum-guy',
      label: 'Bubblegum guy',
      asset: 'assets/images/avatars/19_bubblegum_guy.png',
    ),
    SnapAvatarStyle(
      id: 'cool-cat',
      label: 'Cool cat',
      asset: 'assets/images/avatars/20_cool_cat.png',
    ),
  ];

  /// The stored value for an id: `art:panda`.
  static String encode(String id) => '$prefix$id';

  /// The style a stored avatar value refers to, or null for an emoji or a
  /// value written by a newer build than this one.
  static SnapAvatarStyle? byStored(String? stored) {
    if (stored == null || !stored.startsWith(prefix)) return null;
    final id = stored.substring(prefix.length);
    for (final style in all) {
      if (style.id == id) return style;
    }
    return null;
  }
}

/// A profile picture: the chosen illustration when the profile holds one, or
/// the stored emoji / first letter otherwise.
class SnapAvatar extends StatelessWidget {
  const SnapAvatar({
    super.key,
    required this.avatar,
    this.size = 64,
    this.fallbackInitial,
    this.showEditBadge = false,
  });

  /// The value from [DietProfile.avatar] — `art:<id>` or a legacy emoji.
  final String? avatar;

  final double size;

  /// Shown when there is neither an illustrated avatar nor an emoji.
  final String? fallbackInitial;

  /// A small pencil in the corner, for the one place the avatar is editable.
  final bool showEditBadge;

  @override
  Widget build(BuildContext context) {
    final style = SnapAvatars.byStored(avatar);
    final badge = showEditBadge ? _EditBadge(size: size) : null;

    if (style == null) {
      final letter = fallbackInitial?.trim();
      final text = (avatar == null || avatar!.isEmpty)
          ? (letter == null || letter.isEmpty ? 'U' : letter[0].toUpperCase())
          : avatar!;
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: MacroSnapTheme.accentGradient,
                shape: BoxShape.circle,
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
            ?badge,
          ],
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: Image.asset(
              style.asset,
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              // A missing asset must not paint Flutter's error glyph into a
              // leaderboard row: fall back to the initial the row would have
              // shown without an avatar.
              errorBuilder: (context, error, stack) => Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                color: MacroSnapTheme.neonOrange,
                child: Text(
                  _initial(fallbackInitial),
                  style: TextStyle(
                    fontSize: size * 0.42,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
          // A screen reader should hear who the picture is, not "image".
          Semantics(
            label: '${style.label} avatar',
            child: const SizedBox.expand(),
          ),
          ?badge,
        ],
      ),
    );
  }

  static String _initial(String? name) {
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty ? 'U' : trimmed[0].toUpperCase();
  }
}

class _EditBadge extends StatelessWidget {
  const _EditBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = size * 0.36;
    return Positioned(
      right: -2,
      bottom: -2,
      child: Container(
        width: badge,
        height: badge,
        decoration: BoxDecoration(
          color: MacroSnapTheme.neonOrange,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? MacroSnapTheme.cardDark
                : Colors.white,
            width: 2.5,
          ),
        ),
        child: Icon(
          Icons.edit_rounded,
          size: badge * 0.52,
          color: Colors.black,
        ),
      ),
    );
  }
}

/// Bottom sheet that lets the user choose an illustrated avatar.
///
/// Returns the stored value (`art:<id>`) or null when dismissed.
Future<String?> showSnapAvatarPicker(
  BuildContext context, {
  String? current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return Container(
        decoration: BoxDecoration(
          color: isDark ? MacroSnapTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.textTertiary(ctx),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Choose your avatar',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'You can change this any time.',
                style: TextStyle(
                  fontSize: 12,
                  color: MacroSnapTheme.textSecondary(ctx),
                ),
              ),
              const SizedBox(height: 18),
              // Twenty tiles is five rows on a phone: scroll rather than
              // relying on the sheet being tall enough on a small screen.
              ConstrainedBox(
                // Tall enough for five rows of full-width tiles on a typical
                // phone, short enough that the sheet never swallows the page.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.66,
                ),
                child: SingleChildScrollView(
                  // Four columns that FILL the sheet. Fixed-size tiles in a
                  // Wrap could not spend the leftover width, so four 58 px
                  // circles sat against the left padding with a dead strip on
                  // the right. The tile is derived from the sheet width instead,
                  // which keeps the grid symmetrical on every screen.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const spacing = 12.0;
                      const columns = 4;
                      final fitted =
                          (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;
                      // Capped so a tablet does not paint four dinner-plate
                      // faces; whatever is left over is then centred rather
                      // than pushed to one side.
                      final tile = fitted > _AvatarChoice.maxSize
                          ? _AvatarChoice.maxSize
                          : fitted;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        alignment: tile < fitted
                            ? WrapAlignment.center
                            : WrapAlignment.start,
                        children: [
                          for (final style in SnapAvatars.all)
                            _AvatarChoice(
                              style: style,
                              size: tile,
                              selected:
                                  current == SnapAvatars.encode(style.id),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.style,
    required this.size,
    required this.selected,
  });

  final SnapAvatarStyle style;

  /// The whole tile, ring included. The caller fits this to the sheet width.
  final double size;
  final bool selected;

  /// Largest a tile is allowed to grow on a wide screen.
  /// Largest a tile grows on a wide screen. At 76 four of them plus the
  /// spacing still leave five rows inside the sheet's height cap on a 851 dp
  /// phone, so no face is hidden behind a scroll.
  static const double maxSize = 76;

  /// Ring (2 x 1.5) plus the inner padding (2 x 3) sits between [size] and the
  /// picture, so the picture is this much smaller than its tile.
  static const double _chrome = 9;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      selected: selected,
      label: style.label,
      child: GestureDetector(
        onTap: () {
          Haptics.tap();
          Navigator.pop(context, SnapAvatars.encode(style.id));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? MacroSnapTheme.neonOrange
                  : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
              width: selected ? 2.5 : 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SnapAvatar(
                avatar: SnapAvatars.encode(style.id),
                size: size - _chrome,
              ),
              if (selected)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: MacroSnapTheme.neonOrange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.black,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
