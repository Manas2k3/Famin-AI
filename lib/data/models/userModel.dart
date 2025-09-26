class UserModel {
  final String id;
  final String name;
  final String email;
  final DateTime createdAt;     // Account creation timestamp

  // 🔮 Optional fields for later health profile (null by default)
  final int? age;
  final String? gender;         // "female", "other" etc.
  final double? weight;
  final double? height;

  // Pairing fields
  final String? pairingCode; // code this user owns (if they created it)
  final String? partnerId;   // uid of linked partner

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
    this.age,
    this.gender,
    this.weight,
    this.height,
    this.pairingCode,
    this.partnerId,
  });

  /// Convert UserModel → Map (for Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'createdAt': createdAt.toIso8601String(),

      // optional fields
      if (age != null) 'age': age,
      if (gender != null) 'gender': gender,
      if (weight != null) 'weight': weight,
      if (height != null) 'height': height,

      // pairing fields
      if (pairingCode != null) 'pairingCode': pairingCode,
      if (partnerId != null) 'partnerId': partnerId,
    };
  }

  /// Firestore Map → UserModel
  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      id: map['id'] ?? id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),

      // optional fields
      age: map['age'],
      gender: map['gender'],
      weight: (map['weight'] != null) ? (map['weight'] as num).toDouble() : null,
      height: (map['height'] != null) ? (map['height'] as num).toDouble() : null,

      // pairing fields
      pairingCode: map['pairingCode'],
      partnerId: map['partnerId'],
    );
  }
}
