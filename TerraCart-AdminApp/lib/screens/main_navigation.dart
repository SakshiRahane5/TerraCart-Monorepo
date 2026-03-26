import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/theme/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../providers/app_provider.dart';
import '../services/voice_command_bus.dart';
import '../services/voice_intent_service.dart';
import 'attendance/manager_employee_attendance_screen.dart';
import 'customer_requests/customer_requests_screen.dart';
import 'dashboard/captain_dashboard.dart';
import 'dashboard/cook_dashboard.dart';
import 'dashboard/manager_dashboard.dart';
import 'dashboard/waiter_dashboard.dart';
import 'inventory/inventory_screen.dart';
import 'kot/kot_screen.dart';
import 'orders/orders_screen.dart';
import 'payments/payments_screen.dart';
import 'settings/settings_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final SpeechToText _speechToText = SpeechToText();
  final VoiceIntentService _voiceIntentService = VoiceIntentService();
  final Map<String, String> _speechLocalesById = <String, String>{};
  Timer? _voiceListenGuardTimer;
  Offset? _micFabPosition;
  bool _isVoiceListening = false;
  bool _isVoiceProcessing = false;
  bool _isSpeechReady = false;
  bool _voiceResultHandled = false;
  String _voiceTranscript = '';
  String _lastVoiceAssistantReply = '';
  String? _activeVoiceLocaleId;

  static const double _micFabSize = 56;

  static const List<String> _indianSpeechLocalePriority = <String>[
    'hi_IN',
    'en_IN',
    'mr_IN',
    'bn_IN',
    'ta_IN',
    'te_IN',
    'kn_IN',
    'ml_IN',
    'gu_IN',
    'pa_IN',
    'or_IN',
    'as_IN',
    'ur_IN',
  ];

  static const Set<String> _inventoryKeywords = <String>{
    'inventory',
    'stock',
    'restock',
    'refill',
    'purchase',
    'supplier',
    'ingredient',
    'ingredients',
    'bottle',
    'pack',
    'packet',
    'box',
    'kg',
    'kilo',
    'kilogram',
    'kilograms',
    'gram',
    'grams',
    'litre',
    'liter',
    'ml',
    'pcs',
    'piece',
    'pieces',
    'bisleri',
    'à¤‡à¤¨à¥à¤µà¥‡à¤‚à¤Ÿà¤°à¥€',
    'à¤¸à¥à¤Ÿà¥‰à¤•',
    'à¤¸à¤¾à¤®à¤¾à¤¨',
    'à¤¬à¥‹à¤¤à¤²',
    'à¤•à¤¿à¤²à¥‹',
    'à¤²à¥€à¤Ÿà¤°',
    'àª‡àª¨à«àªµà«‡àª¨à«àªŸàª°à«€',
    'àª¸à«àªŸà«‹àª•',
    'àª¬à«‹àªŸàª²',
    'àª•àª¿àª²à«‹',
    'àª²àª¿àªŸàª°',
    'à¤‡à¤‚à¤µà¥à¤¹à¥‡à¤‚à¤Ÿà¤°à¥€',
    'à¤¸à¤¾à¤ à¤¾',
  };

  static const Set<String> _orderKeywords = <String>{
    'order',
    'orders',
    'cart',
    'bill',
    'table',
    'checkout',
    'place',
    'menu',
    'tea',
    'coffee',
    'chai',
    'food',
    'dish',
    'dine',
    'takeaway',
    'à¤‘à¤°à¥à¤¡à¤°',
    'à¤‘à¤°à¥à¤¡à¤°à¥à¤¸',
    'à¤•à¤¾à¤°à¥à¤Ÿ',
    'à¤šà¤¾à¤¯',
    'à¤•à¥‰à¤«à¥€',
    'à¤šà¤¹à¤¾',
    'àª“àª°à«àª¡àª°',
    'àª•àª¾àª°à«àªŸ',
    'àªšàª¾',
    'àª•à«‹àª«à«€',
  };

  static const Set<String> _dashboardKeywords = <String>{
    'dashboard',
    'home',
    'main',
    'overview',
  };

  static const Set<String> _tablesKeywords = <String>{
    'table',
    'tables',
    'dine in',
    'seating',
  };

  static const Set<String> _requestsKeywords = <String>{
    'request',
    'requests',
    'help',
    'support',
  };

  static const Set<String> _settingsKeywords = <String>{
    'settings',
    'setting',
    'preferences',
    'configuration',
  };

  static const Set<String> _paymentsKeywords = <String>{
    'payment',
    'payments',
    'billing',
    'bill',
    'invoice',
  };

  static const Set<String> _kotKeywords = <String>{
    'kot',
    'kitchen',
    'ticket',
  };

  static const Set<String> _employeesKeywords = <String>{
    'employee',
    'employees',
    'staff',
    'attendance',
  };

  static const String _pageDashboard = 'dashboard';
  static const String _pageOrders = 'orders';
  static const String _pageInventory = 'inventory';
  static const String _pageTables = 'tables';
  static const String _pageRequests = 'requests';
  static const String _pageSettings = 'settings';
  static const String _pagePayments = 'payments';
  static const String _pageKot = 'kot';
  static const String _pageEmployees = 'employees';

  static const String _intentDashboard = 'NAV_DASHBOARD';
  static const String _intentInventory = 'NAV_INVENTORY';
  static const String _intentOrders = 'NAV_ORDERS';
  static const String _intentTables = 'NAV_TABLES';
  static const String _intentRequests = 'NAV_REQUESTS';
  static const String _intentSettings = 'NAV_SETTINGS';
  static const String _intentBilling = 'NAV_BILLING';
  static const String _intentKot = 'NAV_KOT';
  static const String _intentEmployees = 'NAV_EMPLOYEES';
  static const String _intentBack = 'NAV_BACK';
  static const String _intentAddItem = 'NAV_ADD_ITEM';
  static const String _intentUnknown = 'UNKNOWN';

  @override
  void dispose() {
    _voiceListenGuardTimer?.cancel();
    _speechToText.stop();
    super.dispose();
  }

  String _normalizeLocaleId(String value) =>
      value.trim().toLowerCase().replaceAll('-', '_');

  String _normalizeVoiceText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.,/#!$%^&*;:{}=\-_`~()+]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool get _supportsSpeechPlugin {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  Map<String, int> _tabIndexMapForRole(String role) {
    switch (role) {
      case 'waiter':
        return const <String, int>{
          _pageDashboard: 0,
          _pageOrders: 1,
          _pageTables: 2,
          _pageRequests: 3,
          _pageSettings: 4,
        };
      case 'cook':
        return const <String, int>{
          _pageDashboard: 0,
          _pageKot: 1,
          _pageInventory: 2,
          _pageSettings: 3,
        };
      case 'captain':
        return const <String, int>{
          _pageDashboard: 0,
          _pageOrders: 1,
          _pageRequests: 2,
          _pageEmployees: 3,
          _pageSettings: 4,
        };
      case 'manager':
        return const <String, int>{
          _pageDashboard: 0,
          _pageOrders: 1,
          _pageInventory: 2,
          _pagePayments: 3,
          _pageSettings: 4,
        };
      default:
        return const <String, int>{
          _pageDashboard: 0,
          _pageOrders: 1,
          _pageTables: 2,
          _pageRequests: 3,
          _pageSettings: 4,
        };
    }
  }

  int? _tabIndexForPage(String role, String page) {
    final mapping = _tabIndexMapForRole(role);
    return mapping[page];
  }

  String? _currentPageForTab(String role) {
    final mapping = _tabIndexMapForRole(role);
    for (final entry in mapping.entries) {
      if (entry.value == _currentIndex) {
        return entry.key;
      }
    }
    return null;
  }

  bool _containsAnyKeyword(String text, Set<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  bool _looksLikeInventoryQuantity(String text) {
    final unitPattern = RegExp(
      r'\b\d+\s*(kg|kilo|kilogram|kilograms|g|gram|grams|l|litre|liter|ml|bottle|box|pack|packet|pcs|piece|pieces|dozen|à¤•à¤¿à¤²à¥‹|à¤—à¥à¤°à¤¾à¤®|à¤²à¥€à¤Ÿà¤°|à¤®à¤¿à¤²à¥€|à¤¬à¥‹à¤¤à¤²|àª•àª¿àª²à«‹|àª—à«àª°àª¾àª®|àª²àª¿àªŸàª°|àª®à«€àª²à«€|àª¬à«‹àªŸàª²)\b',
    );
    return unitPattern.hasMatch(text);
  }

  bool _hasQuantityHint(String text) {
    if (RegExp(r'\b\d+(?:\.\d+)?\b').hasMatch(text)) return true;
    const spokenNumbers = <String>[
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
      'nine',
      'ten',
      'ek',
      'do',
      'teen',
      'char',
      'paanch',
      'chhe',
      'saat',
      'aath',
      'nau',
      'das',
    ];
    return spokenNumbers
        .any((word) => text.contains(' $word ') || text.startsWith('$word '));
  }

  bool _isPureOrderNavigationCommand(String normalizedTranscript) {
    const navWords = <String>[
      'order',
      'orders',
      'open order',
      'open orders',
      'show order',
      'show orders',
      'go to order',
      'go to orders',
      'orders page',
      'order page',
    ];
    final isNav =
        navWords.any((phrase) => normalizedTranscript.contains(phrase));
    if (!isNav) return false;
    return !_hasQuantityHint(' $normalizedTranscript ') &&
        !normalizedTranscript.contains('add') &&
        !normalizedTranscript.contains('takeaway') &&
        !normalizedTranscript.contains('cart') &&
        !normalizedTranscript.contains('item');
  }

  bool _isPureInventoryNavigationCommand(String normalizedTranscript) {
    const navPhrases = <String>[
      'inventory',
      'open inventory',
      'show inventory',
      'go to inventory',
      'inventory page',
      'stock page',
      'open stock',
      'show stock',
    ];
    final isNav =
        navPhrases.any((phrase) => normalizedTranscript.contains(phrase));
    if (!isNav) return false;
    return !_hasQuantityHint(' $normalizedTranscript ') &&
        !normalizedTranscript.contains('add') &&
        !normalizedTranscript.contains('purchase') &&
        !normalizedTranscript.contains('deduct');
  }

  bool _looksLikeNavigationOnlyPhrase(String normalizedTranscript) {
    if (normalizedTranscript.isEmpty) return true;
    final candidates = <String>[
      ..._dashboardKeywords,
      ..._tablesKeywords,
      ..._requestsKeywords,
      ..._settingsKeywords,
      ..._paymentsKeywords,
      ..._kotKeywords,
      ..._employeesKeywords,
      'open',
      'show',
      'go',
      'page',
      'screen',
      'back',
      'previous',
      'dashboard',
      'orders',
      'order',
      'inventory',
      'settings',
      'tables',
      'requests',
      'payments',
      'billing',
      'kot',
      'employees',
    ];

    final words = normalizedTranscript
        .split(' ')
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return true;
    return words.every((w) => candidates.contains(w));
  }

  String _localIntentFromTranscript({
    required String normalizedTranscript,
    required String role,
  }) {
    if (normalizedTranscript.contains('go back') ||
        normalizedTranscript == 'back' ||
        normalizedTranscript.contains('previous')) {
      return _intentBack;
    }

    if (normalizedTranscript.contains('add item') ||
        normalizedTranscript.contains('new item')) {
      return _intentAddItem;
    }

    if (_containsAnyKeyword(normalizedTranscript, _paymentsKeywords)) {
      return _intentBilling;
    }
    if (_containsAnyKeyword(normalizedTranscript, _settingsKeywords)) {
      return _intentSettings;
    }
    if (_containsAnyKeyword(normalizedTranscript, _dashboardKeywords)) {
      return _intentDashboard;
    }
    if (_containsAnyKeyword(normalizedTranscript, _tablesKeywords)) {
      return _intentTables;
    }
    if (_containsAnyKeyword(normalizedTranscript, _requestsKeywords)) {
      return _intentRequests;
    }
    if (_containsAnyKeyword(normalizedTranscript, _kotKeywords)) {
      return _intentKot;
    }
    if (_containsAnyKeyword(normalizedTranscript, _employeesKeywords)) {
      return _intentEmployees;
    }

    final inventoryIntent =
        _containsAnyKeyword(normalizedTranscript, _inventoryKeywords) ||
            _looksLikeInventoryQuantity(normalizedTranscript);
    final orderIntent =
        _containsAnyKeyword(normalizedTranscript, _orderKeywords);

    if (inventoryIntent && !orderIntent) {
      return _intentInventory;
    }
    if (orderIntent && !inventoryIntent) {
      return _intentOrders;
    }
    if (inventoryIntent && orderIntent) {
      if (normalizedTranscript.contains('stock') ||
          normalizedTranscript.contains('inventory')) {
        return _intentInventory;
      }
      return _intentOrders;
    }

    if (_hasQuantityHint(' $normalizedTranscript ')) {
      final inventoryQuantityLike =
          _looksLikeInventoryQuantity(normalizedTranscript) ||
              normalizedTranscript.contains('stock') ||
              normalizedTranscript.contains('inventory') ||
              normalizedTranscript.contains('purchase') ||
              normalizedTranscript.contains('kg') ||
              normalizedTranscript.contains('kilo') ||
              normalizedTranscript.contains('ml') ||
              normalizedTranscript.contains('litre') ||
              normalizedTranscript.contains('liter');
      if (inventoryQuantityLike) {
        return _intentInventory;
      }
      return _intentOrders;
    }

    final currentPage = _currentPageForTab(role);
    if (currentPage == _pageOrders &&
        normalizedTranscript.isNotEmpty &&
        !_isPureOrderNavigationCommand(normalizedTranscript) &&
        !_looksLikeNavigationOnlyPhrase(normalizedTranscript)) {
      return _intentOrders;
    }

    if (currentPage == _pageInventory &&
        normalizedTranscript.isNotEmpty &&
        !_isPureInventoryNavigationCommand(normalizedTranscript) &&
        !_looksLikeNavigationOnlyPhrase(normalizedTranscript)) {
      return _intentInventory;
    }

    return _intentUnknown;
  }

  String? _pageFromIntent(String intent, String role) {
    switch (intent) {
      case _intentDashboard:
        return _pageDashboard;
      case _intentInventory:
      case _intentAddItem:
        return _pageInventory;
      case _intentOrders:
        if (role == 'cook') return _pageKot;
        return _pageOrders;
      case _intentTables:
        return _pageTables;
      case _intentRequests:
        return _pageRequests;
      case _intentSettings:
        return _pageSettings;
      case _intentBilling:
        return _tabIndexForPage(role, _pagePayments) == null
            ? _pageOrders
            : _pagePayments;
      case _intentKot:
        return _pageKot;
      case _intentEmployees:
        return _pageEmployees;
      default:
        return null;
    }
  }

  Future<String> _resolveVoiceIntent({
    required String transcript,
    required String role,
  }) async {
    _lastVoiceAssistantReply = '';
    final normalizedTranscript = _normalizeVoiceText(transcript);
    final localIntent = _localIntentFromTranscript(
      normalizedTranscript: normalizedTranscript,
      role: role,
    );
    var resolvedIntent = localIntent;

    final currentPage = _currentPageForTab(role);

    try {
      final response = await _voiceIntentService.detectIntent(
        transcript: transcript,
        role: role,
        currentPage: currentPage,
      );
      final intent = (response['intent'] ?? _intentUnknown)
          .toString()
          .trim()
          .toUpperCase();
      _lastVoiceAssistantReply =
          (response['assistantReply'] ?? '').toString().trim();
      if (resolvedIntent == _intentUnknown &&
          intent.isNotEmpty &&
          intent != _intentUnknown) {
        resolvedIntent = intent;
      }
    } catch (_) {
      // Fall through to unknown fallback.
    }

    return resolvedIntent;
  }

  String _pageLabel(String page) {
    switch (page) {
      case _pageDashboard:
        return 'dashboard';
      case _pageOrders:
        return 'orders';
      case _pageInventory:
        return 'inventory';
      case _pageTables:
        return 'tables';
      case _pageRequests:
        return 'requests';
      case _pageSettings:
        return 'settings';
      case _pagePayments:
        return 'payments';
      case _pageKot:
        return 'KOT';
      case _pageEmployees:
        return 'employees';
      default:
        return 'screen';
    }
  }

  void _showVoiceSnackBar(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: isError ? AppColors.error : AppColors.primary,
      ),
    );
  }

  Offset _defaultMicPosition(Size size, double bottomInset) {
    return Offset(
      size.width - _micFabSize - 14,
      size.height - _micFabSize - bottomInset,
    );
  }

  Offset _clampMicPosition(
    Offset position,
    Size size, {
    required double topInset,
    required double bottomInset,
  }) {
    final minX = 8.0;
    final maxX = (size.width - _micFabSize - 8).clamp(minX, double.infinity);
    final minY = topInset;
    final maxY =
        (size.height - _micFabSize - bottomInset).clamp(minY, double.infinity);

    return Offset(
      position.dx.clamp(minX, maxX),
      position.dy.clamp(minY, maxY),
    );
  }

  Future<void> _stopGlobalVoiceFlow({bool routeTranscript = true}) async {
    _voiceListenGuardTimer?.cancel();
    _voiceResultHandled = true;
    try {
      await _speechToText.stop();
    } catch (_) {
      // Ignore stop errors from platform edge-cases.
    }

    if (!mounted) return;

    final role = Provider.of<AppProvider>(context, listen: false).userRole;
    final localeId = _activeVoiceLocaleId;
    final transcript = _voiceTranscript.trim();

    setState(() {
      _isVoiceListening = false;
    });

    if (!routeTranscript || transcript.isEmpty) {
      _showVoiceSnackBar(
        'Listening stopped.',
        duration: const Duration(seconds: 1),
      );
      return;
    }

    setState(() {
      _isVoiceProcessing = true;
    });
    try {
      await _routeVoiceCommand(
        transcript: transcript,
        role: role,
        localeId: localeId,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isVoiceProcessing = false;
        });
      }
    }
  }

  String? _pickSpeechLocaleId(String appLanguageCode,
      {String? systemLocaleId}) {
    if (_speechLocalesById.isEmpty) return null;

    final mappedAppLocale = switch (appLanguageCode.trim().toLowerCase()) {
      'hi' => 'hi_IN',
      'mr' => 'mr_IN',
      _ => 'en_IN',
    };

    final candidates = <String>[
      if (systemLocaleId != null && systemLocaleId.trim().isNotEmpty)
        systemLocaleId.trim(),
      mappedAppLocale,
      ..._indianSpeechLocalePriority,
      'en_US',
      'en_GB',
    ];

    for (final candidate in candidates) {
      final matched = _speechLocalesById[_normalizeLocaleId(candidate)];
      if (matched != null && matched.isNotEmpty) {
        return matched;
      }
    }

    for (final entry in _speechLocalesById.entries) {
      if (entry.key.endsWith('_in')) {
        return entry.value;
      }
    }

    return _speechLocalesById.values.first;
  }

  Future<bool> _initializeSpeechEngine(AppProvider appProvider) async {
    if (_isSpeechReady) return true;
    if (!_supportsSpeechPlugin) return false;

    bool available = false;
    try {
      available = await _speechToText.initialize(
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isVoiceListening = false;
            _isVoiceProcessing = false;
          });
          _showVoiceSnackBar(
            error.errorMsg.isEmpty
                ? 'Voice capture failed. Please try again.'
                : error.errorMsg,
            isError: true,
          );
        },
        debugLogging: false,
      );
    } on MissingPluginException {
      _showVoiceSnackBar(
        'Speech plugin missing in current build. Reinstall the app.',
        isError: true,
      );
      return false;
    } on PlatformException catch (e) {
      _showVoiceSnackBar(
        e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Speech initialization failed.',
        isError: true,
      );
      return false;
    }

    if (!available) {
      if (!mounted) return false;
      setState(() {
        _isSpeechReady = false;
      });
      return false;
    }

    final localeMap = <String, String>{};
    String? systemLocaleId;
    try {
      final locales = await _speechToText.locales();
      for (final locale in locales) {
        final localeId = locale.localeId.trim();
        if (localeId.isEmpty) continue;
        localeMap[_normalizeLocaleId(localeId)] = localeId;
      }

      final systemLocale = await _speechToText.systemLocale();
      systemLocaleId = systemLocale?.localeId.trim();
      if (systemLocaleId != null && systemLocaleId.isNotEmpty) {
        localeMap[_normalizeLocaleId(systemLocaleId)] = systemLocaleId;
      }
    } catch (_) {
      // Keep locale map empty and allow plugin default locale fallback.
    }

    if (!mounted) return true;
    setState(() {
      _speechLocalesById
        ..clear()
        ..addAll(localeMap);
      _activeVoiceLocaleId = _pickSpeechLocaleId(
        appProvider.languageCode,
        systemLocaleId: systemLocaleId,
      );
      _isSpeechReady = true;
    });
    return true;
  }

  Future<void> _routeVoiceCommand({
    required String transcript,
    required String role,
    required String? localeId,
  }) async {
    final resolvedIntent = await _resolveVoiceIntent(
      transcript: transcript,
      role: role,
    );
    if (!mounted) return;

    final normalizedTranscript = _normalizeVoiceText(transcript);
    String effectiveIntent = resolvedIntent;
    if (effectiveIntent == _intentUnknown) {
      final currentPage = _currentPageForTab(role);
      if (currentPage == _pageOrders &&
          normalizedTranscript.isNotEmpty &&
          !_isPureOrderNavigationCommand(normalizedTranscript) &&
          !_looksLikeNavigationOnlyPhrase(normalizedTranscript)) {
        effectiveIntent = _intentOrders;
      } else if (currentPage == _pageInventory &&
          normalizedTranscript.isNotEmpty &&
          !_isPureInventoryNavigationCommand(normalizedTranscript) &&
          !_looksLikeNavigationOnlyPhrase(normalizedTranscript)) {
        effectiveIntent = _intentInventory;
      }
    }

    if (effectiveIntent == _intentBack) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop();
      } else if (_currentIndex > 0) {
        setState(() {
          _currentIndex -= 1;
        });
      } else {
        _showVoiceSnackBar(
          'Already at the first page.',
          isError: false,
        );
      }
      return;
    }

    if (effectiveIntent == _intentUnknown) {
      _showVoiceSnackBar(
        _lastVoiceAssistantReply.isNotEmpty
            ? _lastVoiceAssistantReply
            : 'Command not recognized. Please try again.',
        isError: true,
      );
      return;
    }

    final targetPage = _pageFromIntent(effectiveIntent, role) ??
        _currentPageForTab(role) ??
        _pageOrders;
    final targetIndex = _tabIndexForPage(role, targetPage);
    if (targetIndex == null) {
      _showVoiceSnackBar(
        'This command is not available for your role.',
        isError: true,
      );
      return;
    }

    if (mounted && _currentIndex != targetIndex) {
      setState(() {
        _currentIndex = targetIndex;
      });
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    final isPureOrderNavigation =
        _isPureOrderNavigationCommand(normalizedTranscript);
    final isPureInventoryNavigation =
        _isPureInventoryNavigationCommand(normalizedTranscript);
    final shouldDispatchOrderAction = targetPage == _pageOrders &&
        !isPureOrderNavigation &&
        effectiveIntent == _intentOrders &&
        normalizedTranscript.isNotEmpty &&
        !_looksLikeNavigationOnlyPhrase(normalizedTranscript);
    final shouldDispatchInventoryAction = targetPage == _pageInventory &&
        !isPureInventoryNavigation &&
        (effectiveIntent == _intentInventory ||
            effectiveIntent == _intentAddItem ||
            _looksLikeInventoryQuantity(normalizedTranscript) ||
            _hasQuantityHint(' $normalizedTranscript '));

    if (shouldDispatchOrderAction || shouldDispatchInventoryAction) {
      VoiceCommandBus().emit(
        VoiceCommandEvent(
          target: targetPage == _pageOrders
              ? VoiceCommandTarget.orders
              : VoiceCommandTarget.inventory,
          transcript: transcript,
          localeId: localeId,
          autoPlace: false,
        ),
      );
      return;
    }

    _showVoiceSnackBar(
      _lastVoiceAssistantReply.isNotEmpty
          ? _lastVoiceAssistantReply
          : 'Opened ${_pageLabel(targetPage)}.',
      isError: false,
      duration: const Duration(seconds: 1),
    );
  }

  Future<void> _finalizeGlobalVoiceCapture({
    required String role,
    required String? localeId,
  }) async {
    if (_voiceResultHandled) return;
    _voiceResultHandled = true;

    _voiceListenGuardTimer?.cancel();
    try {
      await _speechToText.stop();
    } catch (_) {
      // Ignore stop failures from edge platform states.
    }

    if (!mounted) return;

    setState(() {
      _isVoiceListening = false;
      _isVoiceProcessing = true;
    });

    final transcript = _voiceTranscript.trim();
    if (transcript.isEmpty) {
      _showVoiceSnackBar(
        'Could not hear clearly. Please try again.',
        isError: true,
      );
      if (mounted) {
        setState(() {
          _isVoiceProcessing = false;
        });
      }
      return;
    }

    try {
      await _routeVoiceCommand(
        transcript: transcript,
        role: role,
        localeId: localeId,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isVoiceProcessing = false;
        });
      }
    }
  }

  Future<void> _startGlobalVoiceFlow(AppProvider appProvider) async {
    if (_isVoiceListening || _isVoiceProcessing) return;
    final listeningText = context.tr('nav.voice_listening');

    final speechReady = await _initializeSpeechEngine(appProvider);
    if (!speechReady) {
      _showVoiceSnackBar(
        'Speech recognition is not available on this device.',
        isError: true,
      );
      return;
    }

    final localeId =
        _pickSpeechLocaleId(appProvider.languageCode) ?? _activeVoiceLocaleId;
    final role = appProvider.userRole;

    _voiceListenGuardTimer?.cancel();
    setState(() {
      _activeVoiceLocaleId = localeId;
      _voiceResultHandled = false;
      _voiceTranscript = '';
      _isVoiceListening = true;
      _isVoiceProcessing = false;
    });

    try {
      await _speechToText.listen(
        localeId: localeId,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 20),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (result) {
          if (!mounted) return;
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            setState(() {
              _voiceTranscript = words;
            });
          }
          if (result.finalResult) {
            unawaited(
              _finalizeGlobalVoiceCapture(
                role: role,
                localeId: localeId,
              ),
            );
          }
        },
      );
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _isVoiceListening = false;
          _isVoiceProcessing = false;
        });
      }
      _showVoiceSnackBar(
        'Speech plugin missing in current build. Reinstall the app.',
        isError: true,
      );
      return;
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _isVoiceListening = false;
          _isVoiceProcessing = false;
        });
      }
      _showVoiceSnackBar(
        e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Failed to start voice capture.',
        isError: true,
      );
      return;
    }

    _showVoiceSnackBar(
      listeningText,
      duration: const Duration(seconds: 1),
    );

    _voiceListenGuardTimer = Timer(
      const Duration(seconds: 22),
      () => unawaited(
        _finalizeGlobalVoiceCapture(
          role: role,
          localeId: localeId,
        ),
      ),
    );
  }

  List<Widget> _getScreensForRole(String role) {
    switch (role) {
      case 'waiter':
        return [
          const WaiterDashboard(),
          const OrdersScreen(),
          const OrdersScreen(showTablesOnly: true),
          const CustomerRequestsScreen(showBackButton: false),
          const SettingsScreen(),
        ];
      case 'cook':
        return [
          const CookDashboard(),
          const KotScreen(),
          const InventoryScreen(),
          const SettingsScreen(),
        ];
      case 'captain':
        return [
          const CaptainDashboard(),
          const OrdersScreen(),
          const CustomerRequestsScreen(showBackButton: false),
          const ManagerEmployeeAttendanceScreen(showBackButton: false),
          const SettingsScreen(),
        ];
      case 'manager':
        return [
          const ManagerDashboard(),
          const OrdersScreen(),
          const InventoryScreen(),
          const PaymentsScreen(),
          const SettingsScreen(),
        ];
      default:
        return [
          const WaiterDashboard(),
          const OrdersScreen(),
          const CustomerRequestsScreen(showBackButton: false),
          const SettingsScreen(),
        ];
    }
  }

  IconData? _getIconData(Widget? widget) {
    if (widget is Icon) {
      return widget.icon;
    }
    return null;
  }

  Widget _buildNavItem({
    required BuildContext context,
    required BottomNavigationBarItem item,
    required int index,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final iconData = isSelected
        ? (_getIconData(item.activeIcon) ?? _getIconData(item.icon))
        : _getIconData(item.icon);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 1.5,
                  )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (iconData != null)
                AnimatedScale(
                  scale: isSelected ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: Icon(
                    iconData,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: isSelected ? 22 : 20,
                  ),
                )
              else
                AnimatedScale(
                  scale: isSelected ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: isSelected ? item.activeIcon : item.icon,
                ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: isSelected ? 11 : 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color:
                      isSelected ? AppColors.primary : AppColors.textSecondary,
                  letterSpacing: isSelected ? 0.3 : 0.0,
                  height: 1.0,
                ),
                child: Text(
                  item.label ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              if (isSelected)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(top: 1),
                  width: 3,
                  height: 3,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<BottomNavigationBarItem> _getNavItemsForRole(
    BuildContext context,
    String role,
  ) {
    switch (role) {
      case 'waiter':
        return [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: context.tr('common.dashboard'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: context.tr('common.orders'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.table_restaurant_outlined),
            activeIcon: const Icon(Icons.table_restaurant),
            label: context.tr('common.tables'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.support_agent_outlined),
            activeIcon: const Icon(Icons.support_agent),
            label: context.tr('common.requests'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: context.tr('common.settings'),
          ),
        ];
      case 'cook':
        return [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: context.tr('common.dashboard'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: context.tr('common.kot'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.inventory_2_outlined),
            activeIcon: const Icon(Icons.inventory_2),
            label: context.tr('common.inventory'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: context.tr('common.settings'),
          ),
        ];
      case 'captain':
        return [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: context.tr('common.dashboard'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: context.tr('common.orders'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.support_agent_outlined),
            activeIcon: const Icon(Icons.support_agent),
            label: context.tr('common.requests'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.people_outlined),
            activeIcon: const Icon(Icons.people),
            label: context.tr('common.employees'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: context.tr('common.settings'),
          ),
        ];
      case 'manager':
        return [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: context.tr('common.dashboard'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: context.tr('common.orders'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.inventory_2_outlined),
            activeIcon: const Icon(Icons.inventory_2),
            label: context.tr('common.inventory'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.payment_outlined),
            activeIcon: const Icon(Icons.payment),
            label: context.tr('common.payments'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: context.tr('common.settings'),
          ),
        ];
      default:
        return [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: context.tr('common.dashboard'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: context.tr('common.orders'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.table_restaurant_outlined),
            activeIcon: const Icon(Icons.table_restaurant),
            label: context.tr('common.tables'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.support_agent_outlined),
            activeIcon: const Icon(Icons.support_agent),
            label: context.tr('common.requests'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: context.tr('common.settings'),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final isVoiceEnabled = appProvider.voiceCommands;
    final userRole = appProvider.userRole;

    final screens = _getScreensForRole(userRole);
    final navItems = _getNavItemsForRole(context, userRole);

    if (_currentIndex >= screens.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final topInset = MediaQuery.of(context).padding.top + 8;
          final bottomInset = MediaQuery.of(context).padding.bottom + 86;
          final currentMicPosition = _clampMicPosition(
            _micFabPosition ?? _defaultMicPosition(size, bottomInset),
            size,
            topInset: topInset,
            bottomInset: bottomInset,
          );

          return Stack(
            children: [
              IndexedStack(
                index: _currentIndex,
                children: screens,
              ),
              if (isVoiceEnabled)
                Positioned(
                  left: currentMicPosition.dx,
                  top: currentMicPosition.dy,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final base = _micFabPosition ?? currentMicPosition;
                      setState(() {
                        _micFabPosition = _clampMicPosition(
                          base + details.delta,
                          size,
                          topInset: topInset,
                          bottomInset: bottomInset,
                        );
                      });
                    },
                    child: SizedBox(
                      width: _micFabSize,
                      height: _micFabSize,
                      child: FloatingActionButton(
                        heroTag: 'voice_command_fab',
                        onPressed: () => unawaited(
                          _isVoiceListening
                              ? _stopGlobalVoiceFlow(routeTranscript: true)
                              : _startGlobalVoiceFlow(appProvider),
                        ),
                        backgroundColor: _isVoiceListening
                            ? AppColors.success
                            : _isVoiceProcessing
                                ? AppColors.warning
                                : AppColors.primary,
                        child: Icon(
                          _isVoiceListening
                              ? Icons.hearing
                              : _isVoiceProcessing
                                  ? Icons.sync
                                  : Icons.mic,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            height: 65,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                navItems.length,
                (index) => _buildNavItem(
                  context: context,
                  item: navItems[index],
                  index: index,
                  isSelected: _currentIndex == index,
                  onTap: () {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
