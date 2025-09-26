import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class HeightWeightController extends GetxController {
  final box = GetStorage();

  // Height (metric) range: 100..220 cm
  final List<int> heightsCm = List<int>.generate(121, (i) => 100 + i); // 100..220
  // Weight (metric) range: 30..150 kg
  final List<int> weightsKg = List<int>.generate(121, (i) => 30 + i); // 30..150

  // Observables to track selection (index in list)
  final RxInt selectedHeightIndex = 70.obs; // default ~170 cm -> index 70 = 170 (100+70)
  final RxInt selectedWeightIndex = 40.obs; // default ~70 kg -> 30+40=70

  // toggle: true => Metric, false => Imperial
  final RxBool heightIsMetric = true.obs;
  final RxBool weightIsMetric = true.obs;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Helpers to get currently selected numeric values
  int get selectedHeightCm => heightsCm[selectedHeightIndex.value];
  String get selectedHeightDisplay {
    if (heightIsMetric.value) {
      return '${selectedHeightCm.toString()} cm';
    } else {
      final feetInches = cmToFeetInches(selectedHeightCm);
      return '${feetInches['ft']} ft ${feetInches['in']} in';
    }
  }

  int get selectedWeightKg => weightsKg[selectedWeightIndex.value];
  String get selectedWeightDisplay {
    if (weightIsMetric.value) {
      return '${selectedWeightKg.toString()} kg';
    } else {
      final lbs = (_kgToLbs(selectedWeightKg)).round();
      return '$lbs lb';
    }
  }

  Future<void> saveLocally() async {
    box.write('pending_height_cm', selectedHeightCm);
    box.write('pending_height_display', selectedHeightDisplay);
    box.write('pending_weight_kg', selectedWeightKg);
    box.write('pending_weight_display', selectedWeightDisplay);
  }

  // Optional: call this to clear local pending values after they have been uploaded
  void clearPendingLocal() {
    box.remove('pending_height_cm');
    box.remove('pending_height_display');
    box.remove('pending_weight_kg');
    box.remove('pending_weight_display');
  }

  Map<String,int> cmToFeetInches(int cm) {
    final totalInches = cm / 2.54;
    final ft = totalInches ~/ 12;
    final inches = (totalInches - (ft * 12)).round();
    return {'ft': ft, 'in': inches};
  }

  double _kgToLbs(int kg) => kg * 2.2046226218;

  // Public: toggle metric/imperial
  void toggleHeightUnit(bool value) => heightIsMetric.value = value;
  void toggleWeightUnit(bool value) => weightIsMetric.value = value;

  // Update index when user scrolls the wheel
  void updateHeightIndex(int index) => selectedHeightIndex.value = index;
  void updateWeightIndex(int index) => selectedWeightIndex.value = index;

  /// Save the currently selected height+weight to Firestore for the current user.
  /// Writes both metric and imperial forms:
  ///  - height_cm (int)
  ///  - height_ft (int)
  ///  - height_in (int)
  ///  - height_display (string)
  ///  - weight_kg (int)
  ///  - weight_lbs (double, rounded to 1 decimal)
  Future<void> saveHeightAndWeightToFirestore({bool saveHeight = true, bool saveWeight = true}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No authenticated user.');

    final docRef = _firestore.collection('Users').doc(user.uid);

    final Map<String, dynamic> data = {};

    if (saveHeight) {
      final cm = selectedHeightCm;
      final ftIn = cmToFeetInches(cm);
      data['height_cm'] = cm;
      data['height_ft'] = ftIn['ft'];
      data['height_in'] = ftIn['in'];
      data['height_display'] = heightIsMetric.value ? '$cm cm' : '${ftIn['ft']} ft ${ftIn['in']} in';
    }

    if (saveWeight) {
      final kg = selectedWeightKg;
      final lbs = double.parse((_kgToLbs(kg)).toStringAsFixed(1));
      data['weight_kg'] = kg;
      data['weight_lbs'] = lbs;
      data['weight_display'] = weightIsMetric.value ? '$kg kg' : '$lbs lb';
    }

    // merge = true so we don't overwrite other fields
    await docRef.set(data, SetOptions(merge: true));
  }
}
