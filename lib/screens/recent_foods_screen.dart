import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../services/recent_food_service.dart';
import '../services/meal_store.dart';
import '../widgets/animations.dart';

/// Screen showing recently scanned foods for quick re-add.
///
/// Users can tap a food to instantly log it, or swipe to delete.
class RecentFoodsScreen extends StatefulWidget {
  const RecentFoodsScreen({super.key});

  @override
  State<RecentFoodsScreen> createState() => _RecentFoodsScreenState();
}

class _RecentFoodsScreenState extends State<RecentFoodsScreen> {
  String _searchQuery = '';

  /// The active tag chip, or null for "All". One chip at a time: the row is a
  /// quick way into a kind of food, not a saved view.
  String? _activeTag;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RecentFood> get _filteredFoods {
    final base = _searchQuery.isEmpty
        ? RecentFoodService.instance.sortedFoods
        : RecentFoodService.instance.search(_searchQuery);
    if (_activeTag == null) return base;
    // '★' filters the starred foods; any other value is a [RecentFood.tag].
    if (_activeTag == '★') {
      return base.where((f) => f.favorite).toList();
    }
    return base.where((f) => f.tag == _activeTag).toList();
  }

  Future<void> _toggleFavorite(RecentFood food) async {
    await RecentFoodService.instance.toggleFavorite(food.id);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          food.favorite
              ? 'Removed "${food.name}" from favorites'
              : '"${food.name}" favorited — it now sits at the top',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _logFood(RecentFood food) async {
    // Log the meal
    MealStore.instance.add(food.toMealRecord());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Logged "${food.name}" (${food.calories} kcal)'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: MacroSnapTheme.neonGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteFood(RecentFood food) async {
    await RecentFoodService.instance.remove(food.id);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${food.name}"'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? MacroSnapTheme.cardDark
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All Recent Foods'),
        content: const Text('This will remove all saved foods. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: MacroSnapTheme.neonPink,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await RecentFoodService.instance.clear();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foods = _filteredFoods;

    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Recent Foods',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (foods.isNotEmpty)
            IconButton(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_rounded, size: 22),
              tooltip: 'Clear all',
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search recent foods...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.clear_rounded, size: 18),
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2A2A32)
                    : const Color(0xFFF5F3FF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          // Tag filter row: All · ★ · the derived categories. Only when there
          // is anything saved — an empty list gets nothing but the empty state.
          if (RecentFoodService.instance.foods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _tagChip('All', null, isDark),
                    const SizedBox(width: 8),
                    _tagChip('★ Favorites', '★', isDark),
                    for (final tag in RecentFood.tags) ...[
                      const SizedBox(width: 8),
                      _tagChip(tag, tag, isDark),
                    ],
                  ],
                ),
              ),
            ),

          // Stats header
          if (foods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Text(
                    '${foods.length} food${foods.length == 1 ? '' : 's'} saved',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MacroSnapTheme.textTertiary(context),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tap to log · Long-press to favorite · Swipe to delete',
                    style: TextStyle(
                      fontSize: 12,
                      color: MacroSnapTheme.textQuaternary(context),
                    ),
                  ),
                ],
              ),
            ),

          // Food list
          Expanded(
            child: foods.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: foods.length,
                    itemBuilder: (context, index) {
                      final food = foods[index];
                      return AnimatedEntrance(
                        delayMs: index * 30,
                        child: _buildFoodCard(food, isDark),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: MacroSnapTheme.neonGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.restaurant_rounded,
              color: MacroSnapTheme.neonGreen,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'No recent foods yet'
                : 'No foods match your search',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Scan a food and it will appear here\nfor quick re-add'
                : 'Try a different search term',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: MacroSnapTheme.textTertiary(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodCard(RecentFood food, bool isDark) {
    // Time ago string
    final diff = DateTime.now().difference(food.scannedAt);
    String timeAgo;
    if (diff.inMinutes < 60) {
      timeAgo = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      timeAgo = '${diff.inHours}h ago';
    } else {
      timeAgo = '${diff.inDays}d ago';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: Key(food.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Remove Food'),
              content: Text('Remove "${food.name}" from recent foods?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: MacroSnapTheme.neonPink,
                  ),
                  child: const Text('Remove'),
                ),
              ],
            ),
          );
        },
        onDismissed: (_) => _deleteFood(food),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: MacroSnapTheme.neonPink.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.delete_rounded,
            color: MacroSnapTheme.neonPink,
          ),
        ),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _logFood(food);
          },
          // Long-press stars the food, per the recent-foods plan: the next
          // scan-find is faster than typing a search.
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _toggleFavorite(food);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: MacroSnapTheme.habitlyCard(context),
            child: Row(
              children: [
                // Food icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: MacroSnapTheme.neonGreen,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Name + serving
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        food.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          // Category tag
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: MacroSnapTheme.neonCyan.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              food.tag,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: MacroSnapTheme.neonCyan,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Macros
                          Text(
                            'P${food.protein.round()} · C${food.carbs.round()} · F${food.fats.round()}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: MacroSnapTheme.textTertiary(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Time ago
                          Text(
                            timeAgo,
                            style: TextStyle(
                              fontSize: 11,
                              color: MacroSnapTheme.textQuaternary(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Calories badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${food.calories}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: MacroSnapTheme.neonGreen,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Quick add icon
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: MacroSnapTheme.neonGreen,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One chip in the filter row. [value] null means "All"; '★' means the
  /// favorites filter, everything else is a derived [RecentFood.tag].
  Widget _tagChip(String label, String? value, bool isDark) {
    final selected = value == null
        ? _activeTag == null
        : (_activeTag == value);
    return GestureDetector(
      onTap: () => setState(() => _activeTag = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? MacroSnapTheme.neonGreen
              : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected
                ? Colors.black
                : (isDark ? Colors.white70 : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }
}
