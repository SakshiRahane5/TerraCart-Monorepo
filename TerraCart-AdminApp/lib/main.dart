import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/services/api_service.dart';
import 'l10n/app_localizations.dart';
import 'providers/app_provider.dart';
import 'screens/splash_screen.dart';
import 'services/in_app_notification_service.dart';
import 'services/notification_service.dart';
import 'widgets/in_app_notification_overlay.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('[APP][FlutterError] ${details.exceptionAsString()}');
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      debugPrint('[APP][Uncaught] $error');
      debugPrint('[APP][UncaughtStack] $stackTrace');
      return true;
    };

    await _loadDotEnvIfBundled();

    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (error, stackTrace) {
      debugPrint('[APP][Init:orientation] $error');
      debugPrint('[APP][Init:orientation:stack] $stackTrace');
    }

    runApp(const TeraCardApp());

    // Optional plugin/network startup work should never block app boot.
    unawaited(_initializeOptionalServices());
  }, (error, stackTrace) {
    debugPrint('[APP][Zone] $error');
    debugPrint('[APP][ZoneStack] $stackTrace');
  });
}

Future<void> _initializeOptionalServices() async {
  try {
    await ApiService().init();
  } catch (error, stackTrace) {
    debugPrint('[APP][Init:api-service] $error');
    debugPrint('[APP][Init:api-service:stack] $stackTrace');
  }

  try {
    await NotificationService.instance.initialize();
  } catch (error, stackTrace) {
    debugPrint('[APP][Init:notifications] $error');
    debugPrint('[APP][Init:notifications:stack] $stackTrace');
  }
}

Future<void> _loadDotEnvIfBundled() async {
  if (dotenv.isInitialized) {
    return;
  }

  try {
    await dotenv.load(fileName: '.env', isOptional: true);
  } catch (error, stackTrace) {
    debugPrint('[APP][Init:dotenv] skipped: $error');
    debugPrint('[APP][Init:dotenv:stack] $stackTrace');
  }
}

class TeraCardApp extends StatefulWidget {
  const TeraCardApp({super.key});

  @override
  State<TeraCardApp> createState() => _TeraCardAppState();
}

class _TeraCardAppState extends State<TeraCardApp> {
  late final AppProvider _appProvider;
  final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>();

  void _applySystemUiStyle(AppProvider appProvider) {
    final useDarkSurface = appProvider.isDarkMode;
    final useHighContrast = appProvider.highContrast;
    final iconBrightness = useDarkSurface ? Brightness.light : Brightness.dark;
    final navBackground = useDarkSurface
        ? (useHighContrast
            ? AppColors.highContrastPrimary
            : AppColors.backgroundDark)
        : (useHighContrast
            ? AppColors.highContrastSecondary
            : AppColors.background);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: AppColors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness:
            useDarkSurface ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: navBackground,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarDividerColor: AppColors.transparent,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _appProvider = AppProvider();
    InAppNotificationService.instance.attachNavigatorKey(_rootNavigatorKey);
  }

  @override
  void dispose() {
    _appProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppProvider>.value(
      value: _appProvider,
      child: Consumer<AppProvider>(
        builder: (context, appProvider, _) {
          _applySystemUiStyle(appProvider);
          return MaterialApp(
            navigatorKey: _rootNavigatorKey,
            onGenerateTitle: (context) => context.tr('app.name'),
            debugShowCheckedModeBanner: false,
            locale: Locale(appProvider.languageCode),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.lightTheme(
              largeText: appProvider.largeText,
              highContrast: appProvider.highContrast,
              dyslexiaFont: appProvider.dyslexiaFont,
            ),
            darkTheme: AppTheme.darkTheme(
              largeText: appProvider.largeText,
              highContrast: appProvider.highContrast,
              dyslexiaFont: appProvider.dyslexiaFont,
            ),
            themeMode:
                appProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => InAppNotificationOverlay(
              child: child ?? const SizedBox.shrink(),
            ),
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
