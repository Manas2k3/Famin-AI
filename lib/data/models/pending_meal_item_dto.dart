// lib/data/models/pending_meal_item_dto.dart
/// A single user-chosen food entry with explicit unit/servings or grams override.
class PendingMealItemDTO {
  /// Display name or key to search (e.g., "idli", "coconut milk").
  final String name;

  /// Unit selected by the user: 'piece', 'cup', 'ml', '100g', 'serving', etc.
  /// Nullable if the user provided gramsOverride directly.
  final String? unit;

  /// How many of [unit] (ignored if [gramsOverride] is provided).
  final double servings;

  /// If provided, use this exact grams instead of [unit] * [servings].
  final double? gramsOverride;

  const PendingMealItemDTO({
    required this.name,
    required this.unit,
    required this.servings,
    required this.gramsOverride,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'unit': unit,
    'servings': servings,
    'gramsOverride': gramsOverride,
  };
}
