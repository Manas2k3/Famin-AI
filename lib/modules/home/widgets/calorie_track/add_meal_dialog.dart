import 'dart:developer' as dev;
import 'package:famina/utils/string_title_case.dart';
import 'package:flutter/material.dart';

import '../../../../data/models/pending_meal_item_dto.dart';
import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../services/nutrition_api_service.dart';
import 'meal_model.dart';

class AddMealDialog extends StatefulWidget {
  final NutritionRepository repo;
  final MealType initialMealType;

  // Make it async so we can `await` in the dialog
  final Future<void> Function(
      MealType mealType,
      List<PendingMealItemDTO> items,
      ) onMealAdded;

  const AddMealDialog({
    Key? key,
    required this.repo,
    required this.onMealAdded,
    this.initialMealType = MealType.breakfast,
  }) : super(key: key);

  @override
  State<AddMealDialog> createState() => _AddMealDialogState();
}

class _AddMealDialogState extends State<AddMealDialog> {
  MealType _selectedMealType = MealType.breakfast;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _isSubmitting = false;
  bool _isSearching = false;
  List<FoodItem> _results = [];

  // Items the user is preparing to add
  final List<_PendingItem> _pending = [];

  @override
  void initState() {
    super.initState();
    _selectedMealType = widget.initialMealType;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() => _isSearching = true);
    try {
      // repo.api is non-null
      final NutritionApiService api = widget.repo.api;
      final list = await api.searchAll(q);
      setState(() => _results = list);
    } catch (e, st) {
      dev.log('search error', name: 'AddMealDialog', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search failed. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _addToPending(FoodItem f) {
    setState(() {
      _pending.add(_PendingItem(food: f));
    });
  }

  void _removePending(_PendingItem p) {
    setState(() {
      _pending.remove(p);
    });
  }

  Future<void> _submit() async {
    if (_pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one item.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Build DTOs
    final items = _pending.map((p) => PendingMealItemDTO(
      name: p.food.name,
      unit: p.unit,
      servings: p.servings,
      gramsOverride: p.gramsOverride,
    )).toList();

    setState(() => _isSubmitting = true);
    try {
      await widget.onMealAdded(_selectedMealType, items);
      if (!mounted) return;
      Navigator.of(context).pop(); // closes dialog on success
    } catch (e, st) {
      dev.log('add meal failed', name: 'AddMealDialog', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final violet = const Color(0xFF6C5CE7);
    final violetDark = const Color(0xFF5F27CD);

    final screen = MediaQuery.of(context).size;
    final maxDialogHeight = screen.height * 0.85; // keep dialog within viewport
    final bottomInset = MediaQuery.of(context).viewInsets.bottom; // keyboard

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: maxDialogHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            // lets the whole content scroll instead of overflowing
            padding: EdgeInsets.only(bottom: bottomInset + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ----------------- your existing content below -----------------
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Add Meal',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6C5CE7),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: Colors.grey,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const Text(
                  'Meal Type',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: MealType.values.map((mealType) {
                    final isSelected = _selectedMealType == mealType;
                    return ChoiceChip(
                      label: Text(mealType.displayName),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedMealType = mealType;
                          });
                        }
                      },
                      selectedColor: violet,
                      backgroundColor: Colors.grey[200],
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Find a food',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        decoration: InputDecoration(
                          hintText: 'Search (e.g., idli, coconut milk, tea)',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [violet, violetDark]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: _search,
                        icon: const Icon(Icons.search, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                if (_isSearching) const LinearProgressIndicator(),
                const SizedBox(height: 10),

                // Results list (kept scrollable with fixed height)
                if (_results.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final f = _results[i];
                        final per100 =
                            'Per 100 g: ${f.per100gCalories.toStringAsFixed(0)} kcal • '
                            'P ${f.per100gProtein.toStringAsFixed(1)} • '
                            'F ${f.per100gFat.toStringAsFixed(1)} • '
                            'C ${f.per100gCarbs.toStringAsFixed(1)}';
                        final units = f.servings.map((s) => s.unit).join(', ');
                        final unitHint = units.isNotEmpty
                            ? (f.defaultServing != null
                            ? 'Default: ${f.defaultServing} • $units'
                            : units)
                            : 'No serving info (use grams)';
                        return ListTile(
                          dense: true,
                          title: Text(f.name),
                          subtitle: Text('$per100  —  $unitHint'),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _addToPending(f),
                          ),
                        );
                      },
                    ),
                  ),

                if (_results.isNotEmpty) const SizedBox(height: 16),

                // Pending items (let outer scroll handle it)
                if (_pending.isNotEmpty) ...[
                  const Text(
                    'Items to add',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._pending.map((p) {
                    final preview = p.preview();
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.grey[300]!, width: 1.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.food.name.toTitleCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _removePending(p),
                                  icon: const Icon(Icons.close),
                                  color: Colors.red,
                                )
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (p.food.servings.isNotEmpty)
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: p.food.servings.map((s) {
                                  final sel = p.unit == s.unit;
                                  return ChoiceChip(
                                    label: Text(s.description == null
                                        ? s.unit
                                        : '${s.unit} (${s.description})'),
                                    selected: sel,
                                    onSelected: (_) => setState(() {
                                      p.unit = s.unit;
                                    }),
                                    selectedColor:
                                    const Color(0xFF6C5CE7).withOpacity(.15),
                                  );
                                }).toList(),
                              ),
                            if (p.food.servings.isNotEmpty)
                              const SizedBox(height: 10),

                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: p.servings.toString(),
                                    decoration: const InputDecoration(
                                      labelText: 'Servings',
                                      hintText: 'e.g., 1.5',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    onChanged: (v) => setState(() {
                                      p.servings = double.tryParse(v) ?? 1.0;
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: p.gramsOverride?.toString() ?? '',
                                    decoration: const InputDecoration(
                                      labelText: 'Or grams (override)',
                                      hintText: 'e.g., 120',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    onChanged: (v) => setState(() {
                                      p.gramsOverride = v.trim().isEmpty
                                          ? null
                                          : double.tryParse(v);
                                    }),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            Text(
                              'Preview: ${preview['calories']!.toStringAsFixed(0)} kcal • '
                                  'P ${preview['protein']!.toStringAsFixed(1)} g • '
                                  'F ${preview['fat']!.toStringAsFixed(1)} g • '
                                  'C ${preview['carbs']!.toStringAsFixed(1)} g',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [violet, violetDark]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: violet.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        'Add Meal',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),

                  ),
                ),
                // ----------------- end of your content -----------------
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _PendingItem {
  final FoodItem food;
  String? unit;           // chosen serving unit (optional when grams override is used)
  double servings;
  double? gramsOverride;

  _PendingItem({
    required this.food,
    this.unit,
    this.servings = 1.0,
    this.gramsOverride,
  }) {
    unit ??= food.defaultServing ??
        (food.servings.isNotEmpty ? food.servings.first.unit : null);
  }

  Map<String, double> preview() {
    if (gramsOverride != null && gramsOverride! > 0) {
      return food.nutrientsForGrams(gramsOverride!);
    }
    return food.nutrientsForServings(servings, unit: unit);
  }
}
