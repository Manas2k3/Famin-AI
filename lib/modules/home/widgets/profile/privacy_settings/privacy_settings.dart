// lib/pages/profile_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:famina/data/repositories/authentication/authentication_repository.dart';
import 'package:famina/modules/authentication/views/loginPage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PrivacySettings extends StatelessWidget {
  const PrivacySettings({super.key});

  // Settings items shown in the screenshot (you can remove ones not used)
  List<Map<String, dynamic>> get _settings => [
    {
      'title': 'Log Out',
      'icon': Icons.exit_to_app,
      'onTap': () async {
        Get.dialog(
          AlertDialog(
            title: Text("Log out!"),
            content: Text("Are you sure you want to Log out of your account?"),
            actions: [
              TextButton(onPressed: () => Get.back(), child: Text("Cancel")),
              TextButton(
                onPressed: () async {
                  await AuthenticationRepository.instance.logOutAndReset();
                  Get.offAll(() => LoginPage());
                },
                child: Text("Log Out", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
    },
    {
      'title': 'Delete my account',
      'icon': Icons.delete_outline,
      'onTap': () async {
        // initial confirmation
        Get.dialog(
          AlertDialog(
            title: Text("Delete Account"),
            content: Text(
              "Are you sure you want to permanently delete your account? This action cannot be undone.",
            ),
            actions: [
              TextButton(onPressed: () => Get.back(), child: Text("Cancel")),
              TextButton(
                onPressed: () async {
                  Get.back(); // close confirm dialog
                  await _handleAccountDeletion();
                },
                child: Text("Delete", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryText = theme.textTheme.bodyMedium?.copyWith(
      color: Colors.grey[600],
    );

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top bar with close button and optional avatar/name
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                  SizedBox(width: 8),
                  Expanded(child: SizedBox()),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                children: [
                  // Rounded white card with list of settings
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(padding: EdgeInsets.symmetric(vertical: 8)),
                        ..._settings.asMap().entries.map((entry) {
                          final index = entry.key;
                          final s = entry.value;
                          final isLast = index == _settings.length - 1;

                          return Column(
                            children: [
                              ListTile(
                                leading: Icon(s['icon'], color: Colors.black87),
                                title: Text(
                                  s['title'],
                                  style: TextStyle(fontSize: 16),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey[400],
                                ),
                                onTap: s['onTap'],
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                              if (!isLast)
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 60),
                                  child: Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),

                  SizedBox(height: 16),

                  // Privacy info card (teal shield icon + Learn more)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Color(0xFF12907A).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.verified,
                              color: Color(0xFF12907A),
                              size: 28,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your data is protected',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                "Your privacy is our top priority. We'll never sell your data and you can delete it at anytime.",
                                style: secondaryText,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 22),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------
  // Helper functions below
  // ---------------------------

  Future<void> _handleAccountDeletion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar("Error", "No signed in user found.");
      return;
    }

    try {
      // Re-authenticate depending on provider
      final providers = user.providerData.map((e) => e.providerId).toList();

      if (providers.contains('password')) {
        final password = await _askForPassword();
        if (password == null) {
          Get.snackbar("Cancelled", "Account deletion cancelled.");
          return;
        }
        final cred = EmailAuthProvider.credential(
          email: user.email!,
          password: password,
        );
        await user.reauthenticateWithCredential(cred);
      } else if (providers.contains('google.com')) {
      } else {
        // Other providers - ask user to re-login externally
        Get.snackbar(
          "Re-auth required",
          "Please re-login with your provider and try again.",
        );
        return;
      }

      // Proceed with deletion after successful re-auth
      final uid = user.uid;

      // 1) Delete main Users doc
      await FirebaseFirestore.instance.collection('Users').doc(uid).delete();

      // 2) Delete other collections referencing the user (example: 'posts')
      await _deleteCollectionWhereFieldEquals('posts', 'ownerId', uid);
      // Add other collections as needed:
      // await _deleteCollectionWhereFieldEquals('comments', 'uid', uid);
      // await _deleteCollectionWhereFieldEquals('orders', 'userId', uid);

      // 3) Delete Storage files under users/<uid> (recursively)
      await _deleteAllFilesInStoragePath('users/$uid');

      // 4) Delete Firebase Auth user
      await user.delete();

      // 5) Sign out and navigate to login
      await FirebaseAuth.instance.signOut();
      Get.offAll(() => LoginPage());
      Get.snackbar(
        "Deleted",
        "Your account and associated data have been removed.",
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        Get.snackbar(
          "Re-auth required",
          "You need to sign in again before deleting your account.",
        );
      } else {
        Get.snackbar("Auth error", e.message ?? e.code);
      }
    } catch (e) {
      Get.snackbar("Error", "Failed to delete account: $e");
    }
  }

  /// Prompt for password; returns the password or null if cancelled.
  Future<String?> _askForPassword() {
    final controller = TextEditingController();
    bool obscure = true; // <-- keep this OUTSIDE the builder so it persists

    return Get.dialog<String?>(
      AlertDialog(
        title: Text("Confirm password"),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Enter your password to confirm account deletion:"),
                SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    hintText: "Password",
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(result: null), child: Text("Cancel")),
          TextButton(
            onPressed: () => Get.back(result: controller.text.trim()),
            child: Text("Confirm", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }


  /// Delete documents in [collection] where [field] == [value] using batched deletes.
  Future<void> _deleteCollectionWhereFieldEquals(
    String collection,
    String field,
    String value,
  ) async {
    final firestore = FirebaseFirestore.instance;
    const batchLimit = 450; // keep under 500
    Query query = firestore
        .collection(collection)
        .where(field, isEqualTo: value)
        .limit(batchLimit);

    while (true) {
      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) break;

      final batch = firestore.batch();
      for (final doc in snapshot.docs) batch.delete(doc.reference);
      await batch.commit();

      if (snapshot.docs.length < batchLimit) break;
    }
  }

  /// Recursively delete all files under the given storage path.
  Future<void> _deleteAllFilesInStoragePath(String path) async {
    final storage = FirebaseStorage.instance;
    final ref = storage.ref().child(path);

    try {
      final listResult = await ref.listAll();

      // delete files in this folder
      for (final item in listResult.items) {
        await item.delete();
      }

      // recursively delete in subfolders
      for (final prefix in listResult.prefixes) {
        await _deleteAllFilesInStoragePath(prefix.fullPath);
      }
    } catch (e) {
      // ignore if path doesn't exist or other non-fatal error
      // debugPrint('Storage deletion warning for $path: $e');
    }
  }
}
