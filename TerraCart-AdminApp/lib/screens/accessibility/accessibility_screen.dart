import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_provider.dart';

class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accessibility'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
      ),
      body: Consumer<AppProvider>(
        builder: (context, appProvider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppColors.warmGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.accessibility_new_rounded,
                        color: Colors.white,
                        size: 50,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Accessibility Options',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Customize your app experience',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: -0.1),

                const SizedBox(height: 24),

                // Visual Settings
                _buildSectionTitle(
                    context, 'Visual Settings', Icons.visibility),
                const SizedBox(height: 12),

                _buildSettingTile(
                  context,
                  'Dark Mode',
                  'Reduce eye strain in low light',
                  Icons.dark_mode_outlined,
                  appProvider.isDarkMode,
                  () => appProvider.toggleDarkMode(),
                ).animate().fadeIn(delay: 100.ms),

                _buildSettingTile(
                  context,
                  'High Contrast',
                  'Increase color contrast for better visibility',
                  Icons.contrast,
                  appProvider.highContrast,
                  () => appProvider.toggleHighContrast(),
                ).animate().fadeIn(delay: 150.ms),

                _buildSettingTile(
                  context,
                  'Large Text',
                  'Increase text size (20px base)',
                  Icons.text_fields,
                  appProvider.largeText,
                  () => appProvider.toggleLargeText(),
                ).animate().fadeIn(delay: 200.ms),

                _buildSettingTile(
                  context,
                  'Dyslexia-Friendly Font',
                  'Use OpenDyslexic font for easier reading',
                  Icons.font_download_outlined,
                  appProvider.dyslexiaFont,
                  () => appProvider.toggleDyslexiaFont(),
                ).animate().fadeIn(delay: 250.ms),

                const SizedBox(height: 24),

                // Interaction Settings
                _buildSectionTitle(
                    context, 'Interaction Settings', Icons.touch_app),
                const SizedBox(height: 12),

                _buildSettingTile(
                  context,
                  'Voice Commands',
                  'Control the app with your voice',
                  Icons.mic,
                  appProvider.voiceCommands,
                  () => appProvider.toggleVoiceCommands(),
                ).animate().fadeIn(delay: 300.ms),

                _buildSettingTile(
                  context,
                  'Vibration for Orders & Alerts',
                  'Vibrate for new orders, KOT updates, and customer requests',
                  Icons.vibration,
                  appProvider.vibrationEnabled,
                  () => appProvider.toggleVibrationEnabled(),
                ).animate().fadeIn(delay: 350.ms),

                const SizedBox(height: 24),

                // Deaf / Hard of Hearing
                _buildSectionTitle(
                    context, 'Deaf / Hard of Hearing', Icons.hearing_disabled),
                const SizedBox(height: 12),

                _buildSettingTile(
                  context,
                  'Deaf Mode (Preset)',
                  'Enables vibration, visual alerts & flash for all notifications',
                  Icons.accessibility_new,
                  appProvider.deafMode,
                  () => appProvider.toggleDeafMode(),
                ).animate().fadeIn(delay: 360.ms),

                _buildSettingTile(
                  context,
                  'Visual Alerts',
                  'Show prominent visual indicators for new notifications',
                  Icons.notifications_active,
                  appProvider.visualAlerts,
                  () => appProvider.toggleVisualAlerts(),
                ).animate().fadeIn(delay: 370.ms),

                _buildSettingTile(
                  context,
                  'Screen Flash Alerts',
                  'Brief screen flash when important events occur',
                  Icons.flash_on,
                  appProvider.visualFlash,
                  () => appProvider.toggleVisualFlash(),
                ).animate().fadeIn(delay: 380.ms),

                const SizedBox(height: 24),

                // Advanced Settings
                _buildSectionTitle(
                    context, 'Advanced Features', Icons.settings_accessibility),
                const SizedBox(height: 12),

                _buildSettingTile(
                  context,
                  'Smartwatch Sync',
                  'Sync notifications with your smartwatch',
                  Icons.watch,
                  appProvider.smartwatchSync,
                  () => appProvider.toggleSmartwatchSync(),
                ).animate().fadeIn(delay: 400.ms),

                _buildSettingTile(
                  context,
                  'Morse Code Support',
                  'Enable morse code input for accessibility',
                  Icons.radio_button_checked,
                  appProvider.morseCodeSupport,
                  () => appProvider.toggleMorseCodeSupport(),
                ).animate().fadeIn(delay: 450.ms),

                const SizedBox(height: 24),

                // Help Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.info.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.help_outline,
                          color: AppColors.info,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Need Help?',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              'Contact our accessibility support team for assistance.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(
                          Icons.arrow_forward_ios,
                          color: AppColors.info,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 500.ms),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colorScheme.primary, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    bool value,
    VoidCallback onToggle,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final onSurfaceVariant = theme.textTheme.bodySmall?.color ??
        colorScheme.onSurface.withValues(alpha: 0.75);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 8,
        ),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (value ? colorScheme.primary : onSurfaceVariant)
                .withValues(alpha: value ? 0.18 : 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: value ? colorScheme.primary : onSurfaceVariant,
          ),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: onSurfaceVariant,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: (_) => onToggle(),
          activeColor: colorScheme.primary,
        ),
      ),
    );
  }
}
