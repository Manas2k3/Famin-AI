import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'animation_loader.dart';


class FullScreenLoader {
  static bool _isShowing = false;
  static VoidCallback? _onCancel;

  // NEW: live-updating message
  static ValueNotifier<String>? _messageVN;

  static final List<String> _factImages = List.generate(
    9,
        (index) => 'assets/images/loader_facts/fact_${index + 1}.png',
  );

  static bool get isShowing => _isShowing;

  static void openLoadingDialog(String text, String animation, {VoidCallback? onCancel}) {
    if (_isShowing) {
      // If already open, just refresh the message
      _messageVN?.value = text;
      return;
    }

    _isShowing = true;
    _onCancel = onCancel;
    _messageVN = ValueNotifier<String>(text);

    final randomFactImage = (_factImages..shuffle()).first;

    Get.dialog(
      WillPopScope(
        onWillPop: () async {
          _handleCancel();
          return false;
        },
        child: Material(
          color: Colors.white,
          child: Center(
            child: AnimationLoader(
              text: text,                         // initial text (fallback)
              animation: animation,
              listenableText: _messageVN,         // NEW: live updates
            ),
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  // NEW: programmatic message updates
  static void updateText(String text) {
    _messageVN?.value = text;
  }

  static void stopLoading() {
    if (_isShowing) {
      if (Get.isDialogOpen == true) {
        Get.back();
      }
      _isShowing = false;
      _onCancel = null;
      _messageVN?.dispose();
      _messageVN = null;
    }
  }

  static void _handleCancel() {
    _onCancel?.call();
    stopLoading();
  }
}
