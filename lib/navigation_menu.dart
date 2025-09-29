// file: navigation_menu.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'modules/authentication/views/cycleSelectionPage.dart';
import 'modules/scan page/views/scanner_page.dart';
import 'modules/home/views/home_page.dart';
import 'modules/personalisation/history.dart';

class NavigationMenu extends StatelessWidget {
  const NavigationMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NavigationController());

    // Static colors as requested
    final Color backgroundWhite = Colors.white;
    final Color activePink = Colors.pink; // static active icon color
    final Color inactiveColor = Colors.black54; // outlined / inactive icon color
    final Color topBorderColor = Colors.grey.shade200; // subtle top border

    // Theme that customizes label styles based on selected state
    final navTheme = Theme.of(context).copyWith(
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: backgroundWhite,
        indicatorColor: activePink.withOpacity(0.12),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
              (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) {
              return TextStyle(color: activePink, fontWeight: FontWeight.w600, fontSize: 12);
            }
            return TextStyle(color: inactiveColor, fontWeight: FontWeight.w500, fontSize: 12);
          },
        ),
      ),
    );

    return Scaffold(
      // Always white background
      backgroundColor: backgroundWhite,
      bottomNavigationBar: Obx(
            () => Container(
          height: MediaQuery.of(context).size.height * 0.1,
          decoration: BoxDecoration(
            color: backgroundWhite,
            border: Border(
              top: BorderSide(color: topBorderColor, width: 0.5),
            ),
          ),
          child: Theme(
            data: navTheme,
            child: NavigationBar(
              backgroundColor: backgroundWhite, // explicit, though theme already sets it
              height: 80,
              elevation: 0,
              selectedIndex: controller.selectedIndex.value,
              indicatorColor: activePink.withOpacity(0.12),
              onDestinationSelected: (index) => controller.selectedIndex.value = index,
              destinations: [
                // Home
                NavigationDestination(
                  icon: Icon(Icons.home_outlined, color: inactiveColor),
                  selectedIcon: Icon(Icons.home, color: activePink),
                  label: "Home",
                ),

                // Scan
                NavigationDestination(
                  icon: Icon(Icons.qr_code_scanner_outlined, color: inactiveColor),
                  selectedIcon: Icon(Icons.qr_code_scanner, color: activePink),
                  label: "Scan",
                ),

                // History
                NavigationDestination(
                  icon: Icon(Icons.history_outlined, color: inactiveColor),
                  selectedIcon: Icon(Icons.history, color: activePink),
                  label: "History",
                ),

              ],
              // Keep labels only for selected destination (same behavior as before)
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            ),
          ),
        ),
      ),
      body: Obx(
            () => Container(
          color: backgroundWhite, // static white body background
          child: controller.screens[controller.selectedIndex.value],
        ),
      ),
    );
  }
}

class NavigationController extends GetxController {
  final Rx<int> selectedIndex = 0.obs;

  // keep the same order as destinations above
  final screens = [
    HomePage(),
    const ScannerPage(),
    const ScanHistoryPage(),
    CycleSelectionPage()
  ];
}
