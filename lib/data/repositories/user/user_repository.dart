import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../models/userModel.dart';

class UserRepository extends GetxController {
  static UserRepository get instance => Get.find();

  final FirebaseFirestore _db = FirebaseFirestore.instance;


  ///Function to save user dat into the Firestore db
    Future <void> savedUserRecord(UserModel user) async {
      try {
        await _db.collection("Users").doc(user.id).set(user.toMap());
      }on FirebaseAuthException catch (e) {
        throw FirebaseAuthException(message: e.message, code: e.code);
      } on FirebaseException catch (e) {
        throw FirebaseException(message: e.message, code: e.code, plugin: '');
      } on FormatException catch (_) {
        throw const FormatException('Invalid format.');
      } on PlatformException catch (e) {
        throw PlatformException(message: e.message, code: e.code);
      } catch (e) {
        throw 'Something went wrong. Please try again.';
      }
    }
}