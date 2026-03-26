import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../services/app_update_service.dart';

class ForceUpdateScreen extends StatefulWidget {
  final AppUpdateDecision decision;

  const ForceUpdateScreen({
    super.key,
    required this.decision,
  });

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  bool _isLaunching = false;
  String? _launchError;

  Future<void> _launchUpdate() async {
    final target = widget.decision.preferredUpdateUrl;
    if (target == null || target.isEmpty) {
      setState(() {
        _launchError =
            'Update URL is not available. Please contact your administrator.';
      });
      return;
    }

    final uri = Uri.tryParse(target);
    if (uri == null) {
      setState(() {
        _launchError = 'Invalid update URL: $target';
      });
      return;
    }

    setState(() {
      _isLaunching = true;
      _launchError = null;
    });

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        setState(() {
          _launchError =
              'Could not open update URL. Please try again in a moment.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _launchError = 'Could not open update URL. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLaunching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = widget.decision;
    final notes = decision.releaseNotes.trim();

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.system_update_alt,
                    size: 34,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Update Required',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'A newer app version is required to continue.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 18),
                _buildVersionRow('Current Version', decision.currentVersion),
                _buildVersionRow('Latest Version', decision.latestVersion),
                _buildVersionRow(
                  'Minimum Supported',
                  decision.minimumSupportedVersion,
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Release Notes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.cardBorder,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          notes,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    height: 1.45,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (_launchError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _launchError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLaunching ? null : _launchUpdate,
                    icon: _isLaunching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download),
                    label: Text(_isLaunching ? 'Opening...' : 'Update Now'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
