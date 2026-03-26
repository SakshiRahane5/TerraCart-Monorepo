import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../auth/login_screen.dart';
import '../accessibility/accessibility_screen.dart';
import 'work_schedule_screen.dart';
import 'attendance_history_screen.dart';
import 'emergency_contacts_screen.dart';
import 'apply_leave_screen.dart';
import 'personal_info_screen.dart';
import 'notifications_screen.dart';
import 'language_screen.dart';
import 'help_faq_screen.dart';
import 'contact_support_screen.dart';
import 'about_app_screen.dart';
import 'printer_config_screen.dart';
import '../attendance/manager_employee_attendance_screen.dart';
import '../compliance/compliance_screen.dart';
import '../checklists/checklists_screen.dart';
import '../../services/kot_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final KotService _kotService = KotService();
  String _appVersion = '--';
  bool _isLoggingOut = false;
  bool _isClearingKot = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = info.version.trim().isEmpty ? '--' : info.version.trim();
      });
    } catch (_) {
      // Keep fallback version text when package info is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final userName = appProvider.userName.isNotEmpty
        ? appProvider.userName
        : context.tr('common.staff_member');
    final userRole = appProvider.userRole;
    final roleLabel = context.tr('role.$userRole');
    final languageLabel = switch (appProvider.languageCode) {
      'hi' => context.tr('language.hindi'),
      'mr' => context.tr('language.marathi'),
      _ => context.tr('language.english'),
    };
    final workItems = <_MenuItem>[
      _MenuItem(
        icon: Icons.checklist,
        title: context.tr('settings.daily_checklists'),
        subtitle: context.tr('settings.tasks'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ChecklistsScreen(showBackButton: true),
            ),
          );
        },
      ),
      _MenuItem(
        icon: Icons.schedule,
        title: context.tr('settings.work_schedule'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const WorkScheduleScreen(),
            ),
          );
        },
      ),
      _MenuItem(
        icon: Icons.event_busy,
        title: context.tr('settings.apply_leave'),
        subtitle: context.tr('settings.choose_dates_reason'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ApplyLeaveScreen(),
            ),
          );
        },
      ),
      _MenuItem(
        icon: Icons.access_time,
        title: context.tr('settings.attendance'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AttendanceHistoryScreen(),
            ),
          );
        },
      ),
      _MenuItem(
        icon: Icons.emergency,
        title: context.tr('settings.emergency_contacts'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const EmergencyContactsScreen(),
            ),
          );
        },
      ),
    ];

    if (userRole == 'cook') {
      workItems.add(
        _MenuItem(
          icon: Icons.cleaning_services_outlined,
          title: context.tr('settings.clear_kot'),
          subtitle: context.tr('settings.clear_kot_subtitle'),
          onTap: _isClearingKot ? null : _showClearKotConfirmation,
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Personal Information Section as single button
              _buildMenuSection(
                  context, context.tr('settings.personal_information'), [
                _MenuItem(
                  icon: Icons.person_outline,
                  title: context.tr('settings.personal_information'),
                  subtitle: '$userName - $roleLabel',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PersonalInfoScreen(),
                      ),
                    );
                  },
                ),
              ]).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 16),

              // Work Information
              _buildMenuSection(context, context.tr('settings.work'), workItems)
                  .animate()
                  .fadeIn(delay: 200.ms),

              if (userRole == 'manager') ...[
                const SizedBox(height: 16),
                _buildMenuSection(context, context.tr('settings.manager'), [
                  _MenuItem(
                    icon: Icons.groups_rounded,
                    title: context.tr('settings.team_attendance'),
                    subtitle: context.tr('settings.manage_checkin_checkout'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const ManagerEmployeeAttendanceScreen(),
                        ),
                      );
                    },
                  ),
                ]).animate().fadeIn(delay: 230.ms),
              ],

              // Printer (Manager only)
              if (userRole == 'manager') ...[
                const SizedBox(height: 16),
                _buildMenuSection(context, context.tr('settings.printer'), [
                  _MenuItem(
                    icon: Icons.print,
                    title: context.tr('settings.printer_configuration'),
                    subtitle: context.tr('settings.printer_subtitle'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrinterConfigScreen(),
                        ),
                      );
                    },
                  ),
                ]).animate().fadeIn(delay: 245.ms),
              ],

              // Compliance (Manager only)
              if (userRole == 'manager') ...[
                const SizedBox(height: 16),
                _buildMenuSection(context, context.tr('settings.compliance'), [
                  _MenuItem(
                    icon: Icons.verified_user_outlined,
                    title: context.tr('settings.compliance'),
                    subtitle: context.tr('settings.compliance_subtitle'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ComplianceScreen(),
                        ),
                      );
                    },
                  ),
                ]).animate().fadeIn(delay: 250.ms),
              ],

              const SizedBox(height: 16),

              // Settings
              _buildMenuSection(context, context.tr('common.settings'), [
                _MenuItem(
                  icon: Icons.accessibility_new,
                  title: context.tr('settings.accessibility'),
                  subtitle: context.tr('settings.accessibility_subtitle'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AccessibilityScreen(),
                      ),
                    );
                  },
                ),
                _MenuItem(
                  icon: Icons.notifications_outlined,
                  title: context.tr('settings.notifications'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    );
                  },
                ),
                _MenuItem(
                  icon: Icons.language,
                  title: context.tr('common.language'),
                  subtitle: languageLabel,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LanguageScreen(),
                      ),
                    );
                  },
                ),
                _MenuItem(
                  icon: Icons.dark_mode_outlined,
                  title: context.tr('settings.theme'),
                  subtitle: appProvider.isDarkMode
                      ? context.tr('common.dark')
                      : context.tr('common.light'),
                  onTap: () {
                    appProvider.toggleDarkMode();
                  },
                ),
              ]).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 16),

              // Support
              _buildMenuSection(context, context.tr('settings.support'), [
                _MenuItem(
                  icon: Icons.help_outline,
                  title: context.tr('settings.help_faq'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HelpFAQScreen(),
                      ),
                    );
                  },
                ),
                _MenuItem(
                  icon: Icons.chat_outlined,
                  title: context.tr('settings.contact_support'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ContactSupportScreen(),
                      ),
                    );
                  },
                ),
                _MenuItem(
                  icon: Icons.info_outline,
                  title: context.tr('settings.about_app'),
                  subtitle: context.tr(
                    'common.version',
                    params: {'version': _appVersion},
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AboutAppScreen(),
                      ),
                    );
                  },
                ),
              ]).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 24),

              // Logout Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoggingOut
                      ? null
                      : () {
                    _showLogoutConfirmation(appProvider);
                  },
                  icon: const Icon(Icons.logout, color: AppColors.error),
                  label: Text(
                    context.tr('common.logout'),
                    style: TextStyle(color: AppColors.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuSection(
    BuildContext context,
    String title,
    List<_MenuItem> items,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final onSurfaceVariant = theme.textTheme.bodySmall?.color ??
        colorScheme.onSurface.withValues(alpha: 0.75);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: theme.brightness == Brightness.dark
                    ? Colors.black.withValues(alpha: 0.24)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: theme.brightness == Brightness.dark ? 14 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Column(
                children: [
                  InkWell(
                    onTap: item.onTap,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      enabled: item.onTap != null,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          item.icon,
                          color: colorScheme.primary,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        item.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: item.subtitle != null
                          ? Text(
                              item.subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: onSurfaceVariant,
                              ),
                            )
                          : null,
                      trailing: item.onTap != null
                          ? Icon(
                              Icons.chevron_right,
                              color: onSurfaceVariant,
                            )
                          : null,
                    ),
                  ),
                  if (index < items.length - 1)
                    Divider(
                      height: 1,
                      indent: 70,
                      color: theme.dividerColor,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _showClearKotConfirmation() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(dialogContext.tr('settings.clear_kot_title')),
        content: Text(dialogContext.tr('settings.clear_kot_message')),
        actions: [
          TextButton(
            onPressed:
                _isClearingKot ? null : () => Navigator.pop(dialogContext),
            child: Text(dialogContext.tr('common.cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_isClearingKot) return;
              setState(() => _isClearingKot = true);
              Navigator.pop(dialogContext);

              try {
                await _kotService.clearCookKotHistory();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('settings.clear_kot_success')),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('common.something_went_wrong')),
                    backgroundColor: AppColors.error,
                  ),
                );
              } finally {
                if (mounted) {
                  setState(() => _isClearingKot = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
            ),
            child: _isClearingKot
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(dialogContext.tr('settings.clear_kot')),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation(AppProvider appProvider) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(dialogContext.tr('settings.logout_title')),
        content: Text(dialogContext.tr('settings.logout_message')),
        actions: [
          TextButton(
            onPressed:
                _isLoggingOut ? null : () => Navigator.pop(dialogContext),
            child: Text(dialogContext.tr('common.cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_isLoggingOut) return;
              setState(() => _isLoggingOut = true);
              Navigator.pop(dialogContext);
              try {
                await appProvider.logout();
                if (!mounted) return;
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('common.something_went_wrong'))),
                );
              } finally {
                if (mounted) {
                  setState(() => _isLoggingOut = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: _isLoggingOut
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(dialogContext.tr('common.logout')),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  _MenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });
}
