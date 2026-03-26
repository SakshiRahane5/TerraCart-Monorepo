import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restart_app/restart_app.dart';

import '../../core/theme/app_colors.dart';
import '../../services/app_update_service.dart';
import '../../services/in_app_update_installer.dart';

enum UpdatePromptResult { later }

class UpdatePromptDialog extends StatefulWidget {
  final AppUpdateDecision decision;

  const UpdatePromptDialog({
    super.key,
    required this.decision,
  });

  @override
  State<UpdatePromptDialog> createState() => _UpdatePromptDialogState();
}

class _UpdatePromptDialogState extends State<UpdatePromptDialog>
    with WidgetsBindingObserver {
  final InAppUpdateInstaller _installer = InAppUpdateInstaller();

  bool _isDownloading = false;
  bool _installerOpened = false;
  bool _isCheckingInstall = false;
  bool _isRestarting = false;
  String? _error;
  int _downloadedBytes = 0;
  int? _totalBytes;

  bool get _isMandatory => widget.decision.updateRequired;

  double? get _progress {
    final total = _totalBytes;
    if (total == null || total <= 0) return null;
    final value = _downloadedBytes / total;
    return value.clamp(0.0, 1.0);
  }

  String _formatProgressText() {
    final total = _totalBytes;
    if (total == null || total <= 0) {
      return 'Downloading update...';
    }
    final progressPercent = ((_progress ?? 0) * 100).toStringAsFixed(0);
    return 'Downloading update... $progressPercent%';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _installerOpened) {
      unawaited(_checkInstalledAndRestart(silent: true));
    }
  }

  Future<void> _startUpdate() async {
    if (_isDownloading || _isCheckingInstall || _isRestarting) return;

    final targetUrl = widget.decision.preferredUpdateUrl;
    if (targetUrl == null || targetUrl.trim().isEmpty) {
      setState(() {
        _error = 'Update URL is unavailable. Please contact administrator.';
      });
      return;
    }

    setState(() {
      _error = null;
      _isDownloading = true;
      _downloadedBytes = 0;
      _totalBytes = null;
    });

    try {
      await _installer.downloadAndOpenInstaller(
        url: targetUrl,
        version: widget.decision.latestVersion,
        onProgress: (downloadedBytes, totalBytes) {
          if (!mounted) return;
          setState(() {
            _downloadedBytes = downloadedBytes;
            _totalBytes = totalBytes;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _installerOpened = true;
      });

      await _checkInstalledAndRestart(silent: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _checkInstalledAndRestart({bool silent = false}) async {
    if (!_installerOpened || _isCheckingInstall || _isRestarting) return;

    setState(() {
      _isCheckingInstall = true;
      if (!silent) _error = null;
    });

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.trim();
      final expectedVersion = widget.decision.latestVersion;

      final updated =
          AppUpdateService.compareVersions(currentVersion, expectedVersion) >= 0;

      if (updated) {
        if (!mounted) return;
        setState(() {
          _isRestarting = true;
          _error = null;
        });
        await Future<void>.delayed(const Duration(milliseconds: 250));
        Restart.restartApp();
        return;
      }

      if (!silent && mounted) {
        setState(() {
          _error =
              'Update not installed yet. Complete installation and tap "Check Install".';
        });
      }
    } catch (error) {
      if (!silent && mounted) {
        setState(() {
          _error = 'Install check failed: ${error.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingInstall = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = widget.decision;
    final notes = decision.releaseNotes.trim();

    return PopScope(
      canPop: !_isMandatory && !_isDownloading && !_isRestarting,
      child: AlertDialog(
        title: Text(
          _isMandatory ? 'Update Required' : 'Update Available',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isMandatory
                    ? 'A newer app version is required to continue.'
                    : 'A newer app version is available.',
              ),
              const SizedBox(height: 12),
              _buildVersionRow('Current', decision.currentVersion),
              _buildVersionRow('Latest', decision.latestVersion),
              _buildVersionRow('Minimum', decision.minimumSupportedVersion),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Release Notes',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(notes),
              ],
              if (_isDownloading) ...[
                const SizedBox(height: 14),
                Text(
                  _formatProgressText(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress),
              ],
              if (_installerOpened) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _isRestarting
                        ? 'Update installed. Restarting app...'
                        : 'Installer opened. Complete installation, then return here.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!_isMandatory && !_isDownloading && !_isRestarting)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(UpdatePromptResult.later),
              child: const Text('Later'),
            ),
          if (_installerOpened && !_isDownloading && !_isRestarting)
            TextButton(
              onPressed: _isCheckingInstall
                  ? null
                  : () => _checkInstalledAndRestart(silent: false),
              child: Text(
                _isCheckingInstall ? 'Checking...' : 'Check Install',
              ),
            ),
          ElevatedButton(
            onPressed: (_isDownloading || _isRestarting)
                ? null
                : _startUpdate,
            child: Text(
              _isDownloading
                  ? 'Downloading...'
                  : _installerOpened
                      ? 'Retry Update'
                      : 'Update Now',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
