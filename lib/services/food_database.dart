class FoodItem {
  final String name;
  final String category;
  final int calories;
  final double protein;
  final double carbs;
  final double fats;
  final double fiber;
  final String serving;

  /// False for meat/fish/egg entries so a vegetarian plan can filter them
  /// out in one pass. Defaults to true - the database is mostly plants.
  final bool isVeg;

  const FoodItem({
    required this.name,
    required this.category,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.fiber,
    required this.serving,
    this.isVeg = true,
  });
}

class FoodDatabase {
  static final List<FoodItem> _items = [
    // --- BREAKFAST ---
    FoodItem(name: 'Idli (2 pcs)', category: 'Breakfast', calories: 156, protein: 5.1, carbs: 34.2, fats: 0.4, fiber: 2.0, serving: '2 pieces'),
    FoodItem(name: 'Dosa (1 plain)', category: 'Breakfast', calories: 133, protein: 3.8, carbs: 25.6, fats: 2.0, fiber: 1.2, serving: '1 medium'),
    FoodItem(name: 'Masala Dosa', category: 'Breakfast', calories: 256, protein: 5.2, carbs: 38.4, fats: 9.6, fiber: 2.8, serving: '1 medium'),
    FoodItem(name: 'Upma', category: 'Breakfast', calories: 280, protein: 7.0, carbs: 48.0, fats: 7.0, fiber: 3.0, serving: '1 plate (200g)'),
    FoodItem(name: 'Poha', category: 'Breakfast', calories: 250, protein: 5.5, carbs: 44.0, fats: 6.0, fiber: 2.5, serving: '1 plate (200g)'),
    FoodItem(name: 'Paratha (Aloo)', category: 'Breakfast', calories: 298, protein: 6.2, carbs: 38.0, fats: 13.5, fiber: 3.0, serving: '1 medium'),
    FoodItem(name: 'Paratha (Plain)', category: 'Breakfast', calories: 210, protein: 5.0, carbs: 32.0, fats: 7.0, fiber: 2.0, serving: '1 medium'),
    FoodItem(name: 'Chole Bhature', category: 'Breakfast', calories: 520, protein: 14.0, carbs: 68.0, fats: 22.0, fiber: 8.0, serving: '1 plate'),
    FoodItem(name: 'Aloo Poha', category: 'Breakfast', calories: 265, protein: 5.8, carbs: 46.0, fats: 6.5, fiber: 3.0, serving: '1 plate'),
    FoodItem(name: 'Vada (1 pc)', category: 'Breakfast', calories: 130, protein: 4.0, carbs: 16.0, fats: 6.0, fiber: 1.5, serving: '1 piece'),
    FoodItem(name: 'Sambar', category: 'Breakfast', calories: 95, protein: 5.0, carbs: 14.0, fats: 2.5, fiber: 4.0, serving: '1 katori (150g)'),
    FoodItem(name: 'Rava Dosa', category: 'Breakfast', calories: 145, protein: 4.0, carbs: 24.0, fats: 4.0, fiber: 1.0, serving: '1 medium'),
    FoodItem(name: 'Methi Thepla', category: 'Breakfast', calories: 170, protein: 5.5, carbs: 26.0, fats: 5.0, fiber: 3.5, serving: '1 piece'),
    FoodItem(name: 'Pongal', category: 'Breakfast', calories: 290, protein: 7.0, carbs: 48.0, fats: 8.0, fiber: 2.0, serving: '1 plate (200g)'),
    FoodItem(name: 'Bread Omelette', category: 'Breakfast', calories: 280, protein: 14.0, carbs: 24.0, fats: 14.0, fiber: 1.0, serving: '2 slices + 2 eggs', isVeg: false),

    // --- LUNCH / DINNER - ROTI & SABZI ---
    FoodItem(name: 'Roti (1 pc)', category: 'Lunch/Dinner', calories: 85, protein: 3.0, carbs: 15.0, fats: 1.0, fiber: 2.5, serving: '1 medium (40g)'),
    FoodItem(name: 'Naan (1 pc)', category: 'Lunch/Dinner', calories: 162, protein: 5.0, carbs: 28.0, fats: 4.0, fiber: 1.0, serving: '1 medium'),
    FoodItem(name: 'Steamed Rice (1 plate)', category: 'Lunch/Dinner', calories: 260, protein: 4.8, carbs: 56.0, fats: 0.6, fiber: 1.0, serving: '1 plate (200g)'),
    FoodItem(name: 'Dal Tadka', category: 'Lunch/Dinner', calories: 145, protein: 9.0, carbs: 16.0, fats: 5.5, fiber: 4.5, serving: '1 katori (150g)'),
    FoodItem(name: 'Dal (Plain)', category: 'Lunch/Dinner', calories: 115, protein: 8.0, carbs: 18.0, fats: 1.5, fiber: 5.0, serving: '1 katori (150g)'),
    FoodItem(name: 'Chole (Chickpea Curry)', category: 'Lunch/Dinner', calories: 210, protein: 10.0, carbs: 28.0, fats: 7.0, fiber: 8.0, serving: '1 katori (150g)'),
    FoodItem(name: 'Rajma (Kidney Bean Curry)', category: 'Lunch/Dinner', calories: 195, protein: 11.0, carbs: 26.0, fats: 5.0, fiber: 7.5, serving: '1 katori (150g)'),
    FoodItem(name: 'Palak Paneer', category: 'Lunch/Dinner', calories: 210, protein: 12.0, carbs: 8.0, fats: 15.0, fiber: 3.0, serving: '1 katori (150g)'),
    FoodItem(name: 'Paneer Butter Masala', category: 'Lunch/Dinner', calories: 310, protein: 14.0, carbs: 12.0, fats: 24.0, fiber: 2.0, serving: '1 katori (150g)'),
    FoodItem(name: 'Aloo Gobi', category: 'Lunch/Dinner', calories: 130, protein: 3.5, carbs: 18.0, fats: 5.5, fiber: 4.0, serving: '1 katori (150g)'),
    FoodItem(name: 'Baingan Bharta', category: 'Lunch/Dinner', calories: 115, protein: 3.0, carbs: 12.0, fats: 6.5, fiber: 5.0, serving: '1 katori (150g)'),
    FoodItem(name: 'Bhindi Masala', category: 'Lunch/Dinner', calories: 120, protein: 3.0, carbs: 10.0, fats: 7.5, fiber: 4.5, serving: '1 katori (150g)'),
    FoodItem(name: 'Mixed Vegetable Curry', category: 'Lunch/Dinner', calories: 125, protein: 3.5, carbs: 16.0, fats: 5.5, fiber: 4.0, serving: '1 katori (150g)'),
    FoodItem(name: 'Dal Makhani', category: 'Lunch/Dinner', calories: 240, protein: 12.0, carbs: 22.0, fats: 12.0, fiber: 6.0, serving: '1 katori (150g)'),
    FoodItem(name: 'Chicken Curry', category: 'Lunch/Dinner', calories: 210, protein: 22.0, carbs: 6.0, fats: 12.0, fiber: 0.5, serving: '1 katori (150g)', isVeg: false),
    FoodItem(name: 'Butter Chicken', category: 'Lunch/Dinner', calories: 290, protein: 24.0, carbs: 10.0, fats: 18.0, fiber: 1.0, serving: '1 katori (150g)', isVeg: false),
    FoodItem(name: 'Fish Curry', category: 'Lunch/Dinner', calories: 185, protein: 20.0, carbs: 5.0, fats: 10.0, fiber: 0.5, serving: '1 katori (150g)', isVeg: false),
    FoodItem(name: 'Egg Curry', category: 'Lunch/Dinner', calories: 200, protein: 13.0, carbs: 8.0, fats: 14.0, fiber: 1.0, serving: '2 eggs + gravy', isVeg: false),
    FoodItem(name: 'Biryani (Veg)', category: 'Lunch/Dinner', calories: 350, protein: 8.0, carbs: 52.0, fats: 12.0, fiber: 3.0, serving: '1 plate (250g)'),
    FoodItem(name: 'Biryani (Chicken)', category: 'Lunch/Dinner', calories: 420, protein: 20.0, carbs: 50.0, fats: 16.0, fiber: 1.5, serving: '1 plate (300g)', isVeg: false),
    FoodItem(name: 'Curd Rice', category: 'Lunch/Dinner', calories: 220, protein: 6.0, carbs: 38.0, fats: 5.0, fiber: 0.5, serving: '1 bowl (200g)'),
    FoodItem(name: 'Lemon Rice', category: 'Lunch/Dinner', calories: 240, protein: 4.5, carbs: 46.0, fats: 4.0, fiber: 1.0, serving: '1 plate (200g)'),
    FoodItem(name: 'Khichdi', category: 'Lunch/Dinner', calories: 260, protein: 8.0, carbs: 48.0, fats: 4.0, fiber: 4.0, serving: '1 plate (250g)'),

    // --- SNACKS & STREET FOOD ---
    FoodItem(name: 'Samosa (1 pc)', category: 'Snacks', calories: 175, protein: 4.0, carbs: 22.0, fats: 8.0, fiber: 1.5, serving: '1 medium'),
    FoodItem(name: 'Pakora (100g)', category: 'Snacks', calories: 280, protein: 6.0, carbs: 22.0, fats: 19.0, fiber: 3.0, serving: '100g'),
    FoodItem(name: 'Pani Puri (1 plate)', category: 'Snacks', calories: 210, protein: 3.5, carbs: 34.0, fats: 7.0, fiber: 3.0, serving: '6 pieces'),
    FoodItem(name: 'Bhel Puri', category: 'Snacks', calories: 160, protein: 4.0, carbs: 28.0, fats: 4.0, fiber: 3.5, serving: '1 plate'),
    FoodItem(name: 'Sev Puri', category: 'Snacks', calories: 210, protein: 4.5, carbs: 28.0, fats: 9.5, fiber: 3.0, serving: '6 pieces'),
    FoodItem(name: 'Vada Pav', category: 'Snacks', calories: 250, protein: 6.0, carbs: 34.0, fats: 10.0, fiber: 2.0, serving: '1 piece'),
    FoodItem(name: 'Pav Bhaji', category: 'Snacks', calories: 380, protein: 8.0, carbs: 48.0, fats: 18.0, fiber: 6.0, serving: '1 plate (2 pav)'),
    FoodItem(name: 'French Fries (medium)', category: 'Snacks', calories: 310, protein: 3.5, carbs: 38.0, fats: 17.0, fiber: 3.0, serving: '1 medium'),
    FoodItem(name: 'Dahi Puri', category: 'Snacks', calories: 180, protein: 5.0, carbs: 26.0, fats: 6.5, fiber: 2.5, serving: '6 pieces'),
    FoodItem(name: 'Sandwich (Grilled)', category: 'Snacks', calories: 230, protein: 10.0, carbs: 32.0, fats: 7.0, fiber: 3.0, serving: '2 slices'),
    FoodItem(name: 'Spring Roll (1 pc)', category: 'Snacks', calories: 120, protein: 3.0, carbs: 14.0, fats: 6.0, fiber: 1.0, serving: '1 piece'),
    FoodItem(name: 'Dhokla (2 pcs)', category: 'Snacks', calories: 140, protein: 5.0, carbs: 22.0, fats: 4.0, fiber: 2.0, serving: '2 pieces'),
    FoodItem(name: 'Kachori (1 pc)', category: 'Snacks', calories: 190, protein: 4.0, carbs: 24.0, fats: 9.0, fiber: 1.5, serving: '1 medium'),
    FoodItem(name: 'Momos (Steamed-6 pcs)', category: 'Snacks', calories: 210, protein: 10.0, carbs: 30.0, fats: 6.0, fiber: 2.0, serving: '6 pieces'),
    FoodItem(name: 'Momos (Fried-6 pcs)', category: 'Snacks', calories: 310, protein: 10.0, carbs: 32.0, fats: 16.0, fiber: 2.0, serving: '6 pieces'),

    // --- SOUTH INDIAN ---
    FoodItem(name: 'Rasam', category: 'South Indian', calories: 45, protein: 2.0, carbs: 8.0, fats: 0.5, fiber: 1.0, serving: '1 katori (150g)'),
    FoodItem(name: 'Appam (1 pc)', category: 'South Indian', calories: 120, protein: 2.0, carbs: 22.0, fats: 3.0, fiber: 1.0, serving: '1 medium'),
    FoodItem(name: 'Puttu', category: 'South Indian', calories: 180, protein: 4.0, carbs: 36.0, fats: 2.0, fiber: 2.5, serving: '1 piece'),
    FoodItem(name: 'Kerala Parotta', category: 'South Indian', calories: 280, protein: 5.0, carbs: 34.0, fats: 14.0, fiber: 1.0, serving: '1 medium'),
    FoodItem(name: 'Uttapam', category: 'South Indian', calories: 200, protein: 6.0, carbs: 30.0, fats: 6.5, fiber: 3.0, serving: '1 medium'),
    FoodItem(name: 'Medu Vada (2 pcs)', category: 'South Indian', calories: 260, protein: 8.0, carbs: 32.0, fats: 12.0, fiber: 3.0, serving: '2 pieces'),
    FoodItem(name: 'Coconut Chutney', category: 'South Indian', calories: 85, protein: 1.0, carbs: 4.0, fats: 7.5, fiber: 2.0, serving: '2 tbsp (30g)'),

    // --- PROTEINS & EGGS ---
    FoodItem(name: 'Boiled Egg (1 pc)', category: 'Proteins', calories: 72, protein: 6.3, carbs: 0.6, fats: 5.0, fiber: 0.0, serving: '1 medium', isVeg: false),
    FoodItem(name: 'Omelette (2 eggs)', category: 'Proteins', calories: 180, protein: 14.0, carbs: 1.5, fats: 13.0, fiber: 0.0, serving: '2 eggs', isVeg: false),
    FoodItem(name: 'Grilled Chicken (100g)', category: 'Proteins', calories: 165, protein: 31.0, carbs: 0.0, fats: 3.6, fiber: 0.0, serving: '100g', isVeg: false),
    FoodItem(name: 'Chicken Tikka (100g)', category: 'Proteins', calories: 190, protein: 28.0, carbs: 4.0, fats: 7.0, fiber: 0.5, serving: '100g (5-6 pieces)', isVeg: false),
    FoodItem(name: 'Fish Fry (100g)', category: 'Proteins', calories: 200, protein: 24.0, carbs: 4.0, fats: 10.0, fiber: 0.0, serving: '100g', isVeg: false),
    FoodItem(name: 'Tandoori Chicken (4 pcs)', category: 'Proteins', calories: 280, protein: 38.0, carbs: 4.0, fats: 12.0, fiber: 0.5, serving: '4 pieces', isVeg: false),
    FoodItem(name: 'Egg Bhurji', category: 'Proteins', calories: 220, protein: 15.0, carbs: 4.0, fats: 16.0, fiber: 0.5, serving: '2 eggs', isVeg: false),
    FoodItem(name: 'Soya Chaap (100g)', category: 'Proteins', calories: 175, protein: 18.0, carbs: 10.0, fats: 7.5, fiber: 4.0, serving: '100g'),
    FoodItem(name: 'Grilled Fish (100g)', category: 'Proteins', calories: 145, protein: 26.0, carbs: 0.0, fats: 4.0, fiber: 0.0, serving: '100g', isVeg: false),

    // --- DAIRY ---
    FoodItem(name: 'Milk (1 glass)', category: 'Dairy', calories: 120, protein: 6.0, carbs: 10.0, fats: 6.5, fiber: 0.0, serving: '1 glass (200ml)'),
    FoodItem(name: 'Curd / Yogurt (1 bowl)', category: 'Dairy', calories: 98, protein: 5.5, carbs: 7.0, fats: 5.0, fiber: 0.0, serving: '1 bowl (150g)'),
    FoodItem(name: 'Buttermilk (1 glass)', category: 'Dairy', calories: 48, protein: 2.5, carbs: 4.5, fats: 2.0, fiber: 0.0, serving: '1 glass (200ml)'),
    FoodItem(name: 'Paneer (100g)', category: 'Dairy', calories: 265, protein: 18.0, carbs: 3.0, fats: 21.0, fiber: 0.0, serving: '100g'),
    FoodItem(name: 'Ghee (1 tbsp)', category: 'Dairy', calories: 115, protein: 0.0, carbs: 0.0, fats: 13.0, fiber: 0.0, serving: '1 tbsp (15g)'),
    FoodItem(name: 'Butter (1 tbsp)', category: 'Dairy', calories: 102, protein: 0.1, carbs: 0.0, fats: 11.5, fiber: 0.0, serving: '1 tbsp (14g)'),
    FoodItem(name: 'Cheese (1 slice)', category: 'Dairy', calories: 84, protein: 5.0, carbs: 0.5, fats: 7.0, fiber: 0.0, serving: '1 slice (20g)'),
    FoodItem(name: 'Lassi (Sweet)', category: 'Dairy', calories: 180, protein: 4.5, carbs: 24.0, fats: 7.5, fiber: 0.0, serving: '1 glass (250ml)'),
    FoodItem(name: 'Lassi (Salted)', category: 'Dairy', calories: 120, protein: 4.0, carbs: 8.0, fats: 8.0, fiber: 0.0, serving: '1 glass (250ml)'),

    // --- BEVERAGES ---
    FoodItem(name: 'Chai (Tea with Milk)', category: 'Beverages', calories: 45, protein: 1.2, carbs: 5.0, fats: 2.5, fiber: 0.0, serving: '1 cup (150ml)'),
    FoodItem(name: 'Coffee with Milk', category: 'Beverages', calories: 35, protein: 1.5, carbs: 4.0, fats: 1.5, fiber: 0.0, serving: '1 cup (150ml)'),
    FoodItem(name: 'Green Tea', category: 'Beverages', calories: 2, protein: 0.1, carbs: 0.3, fats: 0.0, fiber: 0.0, serving: '1 cup'),
    FoodItem(name: 'Fresh Lime Water', category: 'Beverages', calories: 15, protein: 0.1, carbs: 4.0, fats: 0.0, fiber: 0.0, serving: '1 glass'),
    FoodItem(name: 'Coconut Water', category: 'Beverages', calories: 45, protein: 0.5, carbs: 8.0, fats: 0.5, fiber: 1.0, serving: '1 glass (200ml)'),
    FoodItem(name: 'Fruit Juice (Fresh)', category: 'Beverages', calories: 110, protein: 1.0, carbs: 26.0, fats: 0.5, fiber: 0.5, serving: '1 glass (200ml)'),
    FoodItem(name: 'Soft Drink (1 can)', category: 'Beverages', calories: 140, protein: 0.0, carbs: 39.0, fats: 0.0, fiber: 0.0, serving: '1 can (330ml)'),
    FoodItem(name: 'Buttermilk (Chaas)', category: 'Beverages', calories: 48, protein: 2.5, carbs: 4.5, fats: 2.0, fiber: 0.0, serving: '1 glass (200ml)'),
    FoodItem(name: 'Protein Shake (Whey)', category: 'Beverages', calories: 120, protein: 24.0, carbs: 3.0, fats: 1.5, fiber: 0.5, serving: '1 scoop + water'),
    FoodItem(name: 'Smoothie (Fruit)', category: 'Beverages', calories: 180, protein: 4.0, carbs: 34.0, fats: 3.5, fiber: 4.0, serving: '1 glass (250ml)'),
    FoodItem(name: 'Badam Milk', category: 'Beverages', calories: 160, protein: 4.0, carbs: 14.0, fats: 10.0, fiber: 1.5, serving: '1 glass (200ml)'),

    // --- RICE & BREAD BASED ---
    FoodItem(name: 'Jeera Rice', category: 'Rice/Bread', calories: 280, protein: 4.5, carbs: 52.0, fats: 5.5, fiber: 1.0, serving: '1 plate (200g)'),
    FoodItem(name: 'Fried Rice (Veg)', category: 'Rice/Bread', calories: 320, protein: 7.0, carbs: 46.0, fats: 12.0, fiber: 2.5, serving: '1 plate (250g)'),
    FoodItem(name: 'Pulao (Veg)', category: 'Rice/Bread', calories: 300, protein: 6.0, carbs: 48.0, fats: 9.0, fiber: 2.0, serving: '1 plate (200g)'),
    FoodItem(name: 'Bread (Brown-1 slice)', category: 'Rice/Bread', calories: 75, protein: 3.0, carbs: 13.0, fats: 1.0, fiber: 2.0, serving: '1 slice'),
    FoodItem(name: 'Bread (White-1 slice)', category: 'Rice/Bread', calories: 68, protein: 2.0, carbs: 13.0, fats: 0.6, fiber: 0.5, serving: '1 slice'),

    // --- SWEETS & DESSERTS ---
    FoodItem(name: 'Gulab Jamun (2 pcs)', category: 'Sweets', calories: 350, protein: 4.5, carbs: 48.0, fats: 16.0, fiber: 0.5, serving: '2 pieces'),
    FoodItem(name: 'Rasgulla (2 pcs)', category: 'Sweets', calories: 170, protein: 3.0, carbs: 36.0, fats: 2.0, fiber: 0.0, serving: '2 pieces'),
    FoodItem(name: 'Jalebi (100g)', category: 'Sweets', calories: 340, protein: 2.5, carbs: 60.0, fats: 10.0, fiber: 0.5, serving: '100g'),
    FoodItem(name: 'Kheer (1 bowl)', category: 'Sweets', calories: 250, protein: 6.0, carbs: 40.0, fats: 8.0, fiber: 0.5, serving: '1 bowl (150g)'),
    FoodItem(name: 'Halwa (100g)', category: 'Sweets', calories: 380, protein: 5.0, carbs: 50.0, fats: 18.0, fiber: 2.0, serving: '100g'),
    FoodItem(name: 'Ice Cream (1 scoop)', category: 'Sweets', calories: 140, protein: 3.0, carbs: 18.0, fats: 7.0, fiber: 0.0, serving: '1 scoop (60g)'),
    FoodItem(name: 'Laddu (1 pc)', category: 'Sweets', calories: 180, protein: 4.0, carbs: 24.0, fats: 8.0, fiber: 1.0, serving: '1 medium'),
    FoodItem(name: 'Barfi (1 pc)', category: 'Sweets', calories: 150, protein: 3.5, carbs: 20.0, fats: 7.0, fiber: 0.5, serving: '1 piece (30g)'),
    FoodItem(name: 'Kaju Katli (1 pc)', category: 'Sweets', calories: 110, protein: 2.0, carbs: 12.0, fats: 6.5, fiber: 0.3, serving: '1 piece (20g)'),
    FoodItem(name: 'Shrikhand (100g)', category: 'Sweets', calories: 210, protein: 5.0, carbs: 32.0, fats: 8.0, fiber: 0.0, serving: '100g'),

    // --- BAKERY & DESSERTS ---
    // Real per-100g-appropriate values so a cake photo never falls back to an
    // Indian sweet with wrong nutrition (the old 'cake' → 'Barfi' mapping).
    FoodItem(name: 'Chocolate Cake (1 slice)', category: 'Bakery & Desserts', calories: 320, protein: 4.5, carbs: 45.0, fats: 14.0, fiber: 1.5, serving: '1 slice (80g)'),
    FoodItem(name: 'Cupcake (1 pc)', category: 'Bakery & Desserts', calories: 250, protein: 3.0, carbs: 35.0, fats: 11.0, fiber: 1.0, serving: '1 medium (60g)'),
    FoodItem(name: 'Cheesecake (1 slice)', category: 'Bakery & Desserts', calories: 350, protein: 6.0, carbs: 26.0, fats: 25.0, fiber: 0.5, serving: '1 slice (100g)'),
    FoodItem(name: 'Donut (1 pc)', category: 'Bakery & Desserts', calories: 250, protein: 3.5, carbs: 30.0, fats: 13.0, fiber: 1.0, serving: '1 glazed (60g)'),
    FoodItem(name: 'Cookie (1 pc)', category: 'Bakery & Desserts', calories: 80, protein: 1.0, carbs: 10.0, fats: 4.0, fiber: 0.5, serving: '1 medium (20g)'),
    FoodItem(name: 'Brownie (1 pc)', category: 'Bakery & Desserts', calories: 230, protein: 3.0, carbs: 30.0, fats: 12.0, fiber: 1.5, serving: '1 square (55g)'),
    FoodItem(name: 'Croissant (1 pc)', category: 'Bakery & Desserts', calories: 270, protein: 5.0, carbs: 31.0, fats: 14.0, fiber: 1.5, serving: '1 medium (60g)'),
    FoodItem(name: 'Pastry (1 pc)', category: 'Bakery & Desserts', calories: 320, protein: 4.0, carbs: 30.0, fats: 20.0, fiber: 1.0, serving: '1 piece (70g)'),
    FoodItem(name: 'Pancake (2 pcs)', category: 'Bakery & Desserts', calories: 180, protein: 5.0, carbs: 25.0, fats: 7.0, fiber: 1.0, serving: '2 medium'),

    // --- FRUITS ---
    FoodItem(name: 'Banana (1 medium)', category: 'Fruits', calories: 105, protein: 1.3, carbs: 27.0, fats: 0.4, fiber: 3.0, serving: '1 medium'),
    FoodItem(name: 'Apple (1 medium)', category: 'Fruits', calories: 95, protein: 0.5, carbs: 25.0, fats: 0.3, fiber: 4.5, serving: '1 medium'),
    FoodItem(name: 'Orange (1 medium)', category: 'Fruits', calories: 62, protein: 1.2, carbs: 15.0, fats: 0.2, fiber: 3.0, serving: '1 medium'),
    FoodItem(name: 'Mango (1 medium)', category: 'Fruits', calories: 150, protein: 2.0, carbs: 35.0, fats: 0.6, fiber: 5.0, serving: '1 medium (200g)'),
    FoodItem(name: 'Grapes (100g)', category: 'Fruits', calories: 70, protein: 0.7, carbs: 18.0, fats: 0.2, fiber: 1.0, serving: '100g'),
    FoodItem(name: 'Watermelon (1 slice)', category: 'Fruits', calories: 85, protein: 1.5, carbs: 21.0, fats: 0.4, fiber: 1.0, serving: '1 large slice (280g)'),
    FoodItem(name: 'Papaya (100g)', category: 'Fruits', calories: 43, protein: 0.5, carbs: 11.0, fats: 0.2, fiber: 1.7, serving: '100g'),
    FoodItem(name: 'Pomegranate (100g)', category: 'Fruits', calories: 83, protein: 1.7, carbs: 18.7, fats: 1.2, fiber: 4.0, serving: '100g'),
    FoodItem(name: 'Guava (1 medium)', category: 'Fruits', calories: 68, protein: 2.6, carbs: 14.0, fats: 1.0, fiber: 5.4, serving: '1 medium'),
    FoodItem(name: 'Mixed Fruit Bowl', category: 'Fruits', calories: 120, protein: 2.0, carbs: 28.0, fats: 0.5, fiber: 4.0, serving: '1 bowl (200g)'),

    // --- SALADS & SOUPS ---
    FoodItem(name: 'Green Salad (no dressing)', category: 'Salads/Soups', calories: 35, protein: 2.0, carbs: 6.0, fats: 0.5, fiber: 3.5, serving: '1 plate'),
    FoodItem(name: 'Tomato Soup', category: 'Salads/Soups', calories: 85, protein: 2.0, carbs: 14.0, fats: 2.5, fiber: 2.0, serving: '1 bowl (200ml)'),
    FoodItem(name: 'Sweet Corn Soup', category: 'Salads/Soups', calories: 120, protein: 4.0, carbs: 20.0, fats: 3.0, fiber: 2.0, serving: '1 bowl (200ml)'),
    FoodItem(name: 'Cucumber Salad', category: 'Salads/Soups', calories: 25, protein: 1.0, carbs: 5.0, fats: 0.2, fiber: 1.5, serving: '1 plate'),
    FoodItem(name: 'Sprouts Salad (100g)', category: 'Salads/Soups', calories: 110, protein: 8.0, carbs: 18.0, fats: 1.5, fiber: 5.0, serving: '100g'),
  ];

  static List<FoodItem> search(String query) {
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    return _items.where((item) =>
      item.name.toLowerCase().contains(q) ||
      item.category.toLowerCase().contains(q)
    ).toList();
  }

  static List<FoodItem> getByCategory(String category) {
    return _items.where((item) => item.category == category).toList();
  }

  static List<String> get categories => _items.map((e) => e.category).toSet().toList();

  /// Everything a vegetarian can eat, in database order - the source for the
  /// Veg Plan suggestion list.
  static List<FoodItem> get vegetarian => _items.where((e) => e.isVeg).toList();
}
