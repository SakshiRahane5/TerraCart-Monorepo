import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_update_service.dart';

class AboutAppScreen extends StatefulWidget {
  const AboutAppScreen({super.key});

  @override
  State<AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<AboutAppScreen> {
  final AppUpdateService _appUpdateService = AppUpdateService();

  String _version = '--';
  String _buildNumber = '--';
  String _latestVersion = '--';
  String _releaseNotes = 'No release notes available.';
  bool _isLoadingUpdateInfo = true;

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
  }

  Future<void> _loadVersionInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = packageInfo.version.trim().isEmpty
              ? '--'
              : packageInfo.version.trim();
          _buildNumber = packageInfo.buildNumber.trim().isEmpty
              ? '--'
              : packageInfo.buildNumber.trim();
          _latestVersion = _version;
        });
      }
    } catch (_) {
      // Keep fallback values if package info fails.
    } finally {
      await _loadLatestUpdateInfo();
    }
  }

  Future<void> _loadLatestUpdateInfo() async {
    try {
      final decision = await _appUpdateService.checkForMandatoryUpdate(
        timeout: const Duration(seconds: 5),
      );
      if (!mounted) return;

      setState(() {
        if (decision != null) {
          if (decision.latestVersion.trim().isNotEmpty) {
            _latestVersion = decision.latestVersion.trim();
          }
          final notes = decision.releaseNotes.trim();
          if (notes.isNotEmpty) {
            _releaseNotes = notes;
          }
        }
        _isLoadingUpdateInfo = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingUpdateInfo = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateText = _isLoadingUpdateInfo
        ? context.tr('about.checking_latest')
        : context.tr(
            'about.latest_version',
            params: {'version': _latestVersion},
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('about.title')),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox.expand(
                      child: Image.asset(
                        'assets/TerraNewAppLogo_icon.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('app.name'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'about.version_build',
                  params: {'version': _version, 'build': _buildNumber},
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),
              _buildInfoCard(
                context,
                context.tr('about.latest_update'),
                '$updateText\n$_releaseNotes',
                Icons.system_update_alt,
              ),
              _buildInfoCard(
                context,
                context.tr('about.features'),
                context.tr('about.features_list'),
                Icons.apps,
              ),
              _buildInfoCard(
                context,
                context.tr('about.developer'),
                context.tr('about.developer_name'),
                Icons.code,
              ),
              _buildInfoCard(
                context,
                context.tr('about.copyright'),
                context.tr('about.copyright_value'),
                Icons.copyright,
              ),
              _buildInfoCard(
                context,
                context.tr('about.license'),
                context.tr('about.license_value'),
                Icons.verified,
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('about.built_for_accessibility'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
