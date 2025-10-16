// lib/modules/home/widgets/calorie_track/calorie_tracker_screen.dart
import 'dart:developer' as dev;

import 'package:famina/utils/string_title_case.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import 'add_meal_dialog.dart';
import 'meal_model.dart';

class CalorieTrackerScreen extends StatefulWidget {
  const CalorieTrackerScreen({Key? key}) : super(key: key);

  @override
  State<CalorieTrackerScreen> createState() => _CalorieTrackerScreenState();
}

class _CalorieTrackerScreenState extends State<CalorieTrackerScreen> {
  // default ctor now sets up API+assets in your repo
  final NutritionRepository _repository = NutritionRepository();

  DateTime _selectedDate = DateTime.now();
  DailyNutritionSummary? _summary;
  bool _isLoading = true;
  int _streakDays = 1; // (reserved for future streak feature)
  List<DateTime> _weekDates = [];
  Stream<List<MealEntry>>? _mealEntriesStream;

  @override
  void initState() {
    super.initState();
    _generateWeekDates();
    _loadData();
    _setupMealStream();
  }

  void _generateWeekDates() {
    _weekDates = List.generate(7, (index) {
      return _selectedDate.subtract(Duration(days: 3 - index));
    });
  }

  void _setupMealStream() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _mealEntriesStream = _repository.getMealEntriesForDate(
        userId: userId,
        date: _selectedDate,
      );
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final summary = await _repository.getDailySummary(
        userId: userId,
        date: _selectedDate,
      );

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    } catch (e, st) {
      dev.log('Error loading daily summary',
          name: 'CalorieTracker', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddMealDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AddMealDialog(
        repo: _repository,
        initialMealType: MealType.breakfast,
        onMealAdded: (mealType, foods) async {
          final userId = FirebaseAuth.instance.currentUser?.uid;
          if (userId == null) return;

          try {
            await _repository.addMealEntryExact(
              userId: userId,
              mealType: mealType,
              items: foods, // foods is already List<PendingMealItemDTO>
            );
            await _loadData();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Meal added successfully!'),
                backgroundColor: Color(0xFF6C5CE7),
              ),
            );
          } catch (e, st) {
            dev.log('Error adding meal',
                name: 'CalorieTracker', error: e, stackTrace: st);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Something went wrong.')),
            );
          }
        },
      ),
    );
  }

  void _selectDate(DateTime date) {
    setState(() => _selectedDate = date);
    _generateWeekDates();
    _loadData();
    _setupMealStream();
  }

  // ====== delete helpers ======
  Future<bool> _confirmAndDeleteMeal(MealEntry meal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete meal?'),
        content: const Text('This will remove the entry permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return false;

    try {
      await _repository.deleteMealEntry(meal.id);
      await _loadData(); // refresh header cards
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meal deleted')),
      );
      return true;
    } catch (e, st) {
      dev.log('delete meal failed',
          name: 'CalorieTracker', error: e, stackTrace: st);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete meal')),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ===== Header =====
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFF5F27CD)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Calorie Track',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Track your nutrition',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _weekDates.map((date) {
                        final isSelected = date.year == _selectedDate.year &&
                            date.month == _selectedDate.month &&
                            date.day == _selectedDate.day;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => _selectDate(date),
                            child: _buildDayItem(
                              DateFormat('E').format(date).substring(0, 1),
                              '${date.day}',
                              isSelected,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ===== Body =====
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _summary == null
                  ? const Center(child: Text('No data available'))
                  : RefreshIndicator(
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCaloriesCard(),
                      const SizedBox(height: 20),
                      _buildMacrosRow(),
                      const SizedBox(height: 30),
                      _buildRecentMealsHeader(),
                      const SizedBox(height: 12),
                      _buildMealsList(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6C5CE7), Color(0xFF5F27CD)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C5CE7).withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _showAddMealDialog,
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: Colors.white, size: 26),
          label: const Text(
            'Add Meal',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ===== UI pieces =====

  Widget _buildDayItem(String day, String date, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(14),
        border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Column(
        children: [
          Text(
            day,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected ? const Color(0xFF6C5CE7) : Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            date,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isSelected ? const Color(0xFF6C5CE7) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaloriesCard() {
    final remaining = _summary!.recommendedCalories - _summary!.totalCalories;
    final consumed = _summary!.totalCalories;
    final target = _summary!.recommendedCalories;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B6B).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      remaining.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8, left: 4),
                      child: Text(
                        'kcal',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Remaining today',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${consumed.toStringAsFixed(0)} of ${target.toStringAsFixed(0)} consumed',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🔥', style: TextStyle(fontSize: 48)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacrosRow() {
    final proteinTarget = _summary!.recommendedCalories * 0.3 / 4;
    final carbsTarget = _summary!.recommendedCalories * 0.4 / 4;
    final fatTarget = _summary!.recommendedCalories * 0.3 / 9;

    final proteinRemaining = proteinTarget - _summary!.totalProtein;
    final carbsRemaining = carbsTarget - _summary!.totalCarbs;
    final fatRemaining = fatTarget - _summary!.totalFat;

    final proteinProgress =
    (_summary!.totalProtein / proteinTarget).clamp(0.0, 1.0).toDouble();
    final carbsProgress =
    (_summary!.totalCarbs / carbsTarget).clamp(0.0, 1.0).toDouble();
    final fatProgress =
    (_summary!.totalFat / fatTarget).clamp(0.0, 1.0).toDouble();

    final w = MediaQuery.of(context).size.width;
    final isTiny = w < 340;

    final cards = [
      _buildMacroCard(
        '${proteinRemaining.toStringAsFixed(0)}g',
        'Protein',
        'remaining',
        proteinProgress,
        const Color(0xFFFF6B6B),
        '🥩',
      ),
      _buildMacroCard(
        '${carbsRemaining.toStringAsFixed(0)}g',
        'Carbs',
        'remaining',
        carbsProgress,
        const Color(0xFFFECA57),
        '🍞',
      ),
      _buildMacroCard(
        '${fatRemaining.toStringAsFixed(0)}g',
        'Fat',
        'remaining',
        fatProgress,
        const Color(0xFF48DBfB),
        '🧈',
      ),
    ];

    if (isTiny) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(width: (w - 20 - 12) / 2, child: cards[0]),
          SizedBox(width: (w - 20 - 12) / 2, child: cards[1]),
          SizedBox(width: (w - 20 - 12) / 2, child: cards[2]),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 12),
        Expanded(child: cards[1]),
        const SizedBox(width: 12),
        Expanded(child: cards[2]),
      ],
    );
  }

  Widget _buildMacroCard(
      String amount,
      String label,
      String subtitle,
      double progress,
      Color color,
      String emoji,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            amount,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: color.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentMealsHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Recent Meals',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: TextButton.icon(
              onPressed: () {
                // TODO: Navigate to full meal history screen
              },
              icon: const Icon(Icons.arrow_forward,
                  size: 16, color: Color(0xFF6C5CE7)),
              label: const Text(
                'See All',
                style: TextStyle(
                  color: Color(0xFF6C5CE7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMealsList() {
    return StreamBuilder<List<MealEntry>>(
      stream: _mealEntriesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          dev.log('meal_entries stream error',
              name: 'CalorieTracker',
              error: snapshot.error,
              stackTrace: snapshot.stackTrace);
          return _emptyMealsCard();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _emptyMealsCard();
        }

        final meals = snapshot.data!;
        return Column(
          children: meals.map((meal) => _buildMealItem(meal)).toList(),
        );
      },
    );
  }

  Widget _emptyMealsCard() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            const Text('🍽️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text(
              'No meals logged yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap "Add Meal" to start tracking',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  static const _mealTypeImages = {
    MealType.breakfast:
    'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=640',
    MealType.lunch:
    'https://images.unsplash.com/photo-1551218808-94e220e084d2?w=640',
    MealType.dinner:
    'https://images.unsplash.com/photo-1544025162-d76694265947?w=640',
    MealType.quickSnack:
    'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=640',
  };

  String _fmt(double v, {int decimals = 0}) => v.toStringAsFixed(decimals);

  // ===== MEAL ITEM (with swipe + menu delete) =====
  Widget _buildMealItem(MealEntry meal) {
    final emoji = _getMealEmoji(meal.mealType);
    final time = DateFormat('hh:mm a').format(meal.timestamp);
    final img = _mealTypeImages[meal.mealType]!;
    final w = MediaQuery.of(context).size.width;
    final imgSize = w < 360 ? 80.0 : 100.0;

    return Dismissible(
      key: ValueKey(meal.id),
      background: _dismissBg(Alignment.centerLeft),
      secondaryBackground: _dismissBg(Alignment.centerRight),
      confirmDismiss: (_) => _confirmAndDeleteMeal(meal),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Image + Title + Time + Menu
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Meal Image with emoji overlay
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      Image.network(
                        img,
                        width: imgSize,
                        height: imgSize,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: imgSize,
                          height: imgSize,
                          color: Colors.grey[200],
                          child: Icon(Icons.restaurant,
                              color: Colors.grey[400], size: 40),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Text(emoji, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Title, Time, and Menu
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              meal.mealType.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D2A43),
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.more_vert,
                                color: Colors.grey[600], size: 20),
                            tooltip: 'More options',
                            onSelected: (v) async {
                              if (v == 'delete') {
                                await _confirmAndDeleteMeal(meal);
                              }
                            },
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline,
                                        size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete',
                                        style: TextStyle(fontSize: 14)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          time,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6C5CE7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Foods List - bullet style
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE7E8FC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: meal.foods.asMap().entries.map((entry) {
                  final f = entry.value;
                  final isLast = entry.key == meal.foods.length - 1;
                  final subtitle = (f.amount > 0)
                      ? '${_fmt(f.amount)} ${f.unit}'
                      : (f.unit.isNotEmpty ? f.unit : '');

                  return Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF6C5CE7),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF2D2A43),
                                height: 1.4,
                              ),
                              children: [
                                TextSpan(
                                  text: f.name.toTitleCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  TextSpan(
                                    text: ' • ',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                  TextSpan(
                                    text: subtitle,
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 14),

            // Calories and Macros Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Calories
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(
                        '${_fmt(meal.totalCalories)} calories',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D2A43),
                        ),
                      ),
                    ],
                  ),
                  // Macros in compact format
                  _buildCompactMacro('🥩', _fmt(meal.totalProtein)),
                  _buildCompactMacro('🍞', _fmt(meal.totalCarbs)),
                  _buildCompactMacro('🧈', _fmt(meal.totalFat)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactMacro(String emoji, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 4),
        Text(
          '${value}g',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D2A43),
          ),
        ),
      ],
    );
  }

  Widget _dismissBg(Alignment alignment) {
    return Container(
      alignment: alignment,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
    );
  }

  String _getMealEmoji(MealType mealType) {
    switch (mealType) {
      case MealType.breakfast:
        return '🥞';
      case MealType.quickSnack:
        return '🍪';
      case MealType.lunch:
        return '🍱';
      case MealType.dinner:
        return '🍗';
    }
  }
}

extension ColorExtension on Color {
  Color darken(double amount) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final darkened =
    hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return darkened.toColor();
  }
}
