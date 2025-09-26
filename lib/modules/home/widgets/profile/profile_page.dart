// lib/pages/profile_page.dart
import 'package:famina/modules/home/widgets/profile/privacy_settings/privacy_settings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProfilePage extends StatelessWidget {
  final String avatarUrl;
  final String userName;
  final String version;

  ProfilePage({
    Key? key,
    this.avatarUrl = 'https://i.pinimg.com/474x/e6/e4/df/e6e4df26ba752161b9fc6a17321fa286.jpg',
    this.userName = 'You',
    this.version = 'Version 9.85.1',
  }) : super(key: key);

  // Settings items shown in the screenshot (you can remove ones not used)
  List<Map<String, dynamic>> get _settings => [
    {'title': 'App settings', 'icon': Icons.settings, 'onTap': () {}},
    {'title': 'App lock', 'icon': Icons.lock, 'onTap': () {}},
    {'title': 'Graphs & reports', 'icon': Icons.show_chart, 'onTap': () {}},
    {'title': 'Cycle and ovulation', 'icon': Icons.loop, 'onTap': () {}},
    {'title': 'Reminders', 'icon': Icons.notifications, 'onTap': () {}},
    {'title': 'Privacy settings', 'icon': Icons.privacy_tip, 'onTap': (() => Get.to(PrivacySettings())) },
    {'title': 'Help', 'icon': Icons.help_outline, 'onTap': () {}},

  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryText = theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top bar with close button and optional avatar/name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                  SizedBox(width: 8)
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  // Rounded white card with list of settings (like screenshot)
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
                                title: Text(s['title'], style: TextStyle(fontSize: 16)),
                                trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
                                onTap: s['onTap'],
                                contentPadding: EdgeInsets.symmetric(horizontal: 12),
                              ),
                              if (!isLast) // 👈 only show divider if not last item
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
                    )

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
                        // teal shield-ish circle with a check mark to match screenshot
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
                              Text('Your data is protected',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              SizedBox(height: 6),
                              Text(
                                "Your privacy is our top priority. We'll never sell your data and you can delete it at anytime.",
                                style: secondaryText,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 22),

                  // Footer small text (centered)
                  Column(
                    children: [
                      Text('Famin AI',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      SizedBox(height: 4),
                      Text(version, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      SizedBox(height: 8),
                      Text('© 2025 Famin AI.',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        children: [
                          GestureDetector(
                            onTap: () {
                              // open privacy policy
                            },
                            child: Text('Privacy Policy',
                                style: TextStyle(color: Colors.pinkAccent, fontSize: 13)),
                          ),
                          GestureDetector(
                            onTap: () {
                              // open terms
                            },
                            child: Text('Terms of Use',
                                style: TextStyle(color: Colors.pinkAccent, fontSize: 13)),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          // open accessibility statement
                        },
                        child: Text('Accessibility Statement',
                            style: TextStyle(color: Colors.pinkAccent, fontSize: 13)),
                      ),
                      SizedBox(height: 28),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
