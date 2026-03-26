import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/app_provider.dart';
import '../services/app_update_service.dart';
import 'auth/login_screen.dart';
import 'main_navigation.dart';
import 'update/update_prompt_dialog.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AppUpdateService _appUpdateService = AppUpdateService();
  VideoPlayerController? _videoController;
  bool _isVideoReady = false;
  bool _useGifFallback = false;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _initializeSplashMedia();
    _navigateToNextScreen();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initializeSplashMedia() async {
    try {
      final controller =
          VideoPlayerController.asset('assets/TerraCartVideo.mp4');
      _videoController = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();

      if (!mounted) return;
      setState(() {
        _isVideoReady = true;
        _useGifFallback = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _useGifFallback = true;
        _isVideoReady = false;
      });
    }
  }

  Future<void> _navigateToNextScreen() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final initStartTime = DateTime.now();
      final updateCheckFuture = _appUpdateService.checkForMandatoryUpdate();

      int waitCount = 0;
      while (!appProvider.isInitialized && waitCount < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }

      final elapsed = DateTime.now().difference(initStartTime);
      if (elapsed.inMilliseconds < 2200) {
        await Future.delayed(
          Duration(milliseconds: 2200 - elapsed.inMilliseconds),
        );
      }
      final updateDecision = await updateCheckFuture;

      if (!mounted || _hasNavigated) return;

      final destination =
          appProvider.isLoggedIn ? const MainNavigation() : const LoginScreen();

      if (updateDecision != null && updateDecision.shouldPrompt) {
        final modalResult = await showDialog<UpdatePromptResult>(
          context: context,
          barrierDismissible: !updateDecision.updateRequired,
          builder: (_) => UpdatePromptDialog(decision: updateDecision),
        );

        if (!mounted || _hasNavigated) return;

        // Optional update: user can continue with "Later".
        if (!updateDecision.updateRequired &&
            (modalResult == UpdatePromptResult.later || modalResult == null)) {
          _navigateWithFade(destination);
          return;
        }

        // Mandatory update stays blocked in splash until installation/restart.
        if (updateDecision.updateRequired) {
          return;
        }
      }

      _navigateWithFade(destination);
    } catch (error) {
      debugPrint('[SPLASH] Startup navigation failed: $error');
      if (!mounted || _hasNavigated) return;
      _hasNavigated = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _navigateWithFade(Widget destination) {
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  Widget _buildBackgroundMedia() {
    if (!_useGifFallback && _isVideoReady && _videoController != null) {
      final controller = _videoController!;
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }

    return Image.asset(
      'assets/TerraCartGif.gif',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return Container(color: Colors.black);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackgroundMedia(),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
