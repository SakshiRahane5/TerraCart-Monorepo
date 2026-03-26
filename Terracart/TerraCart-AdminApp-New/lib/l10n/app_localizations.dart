import 'package:flutter/material.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('mr'),
  ];

  static AppLocalizations of(BuildContext context) {
    final localizations =
        Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(localizations != null, 'AppLocalizations not found in context');
    return localizations!;
  }

  static String normalizeLanguageCode(String? value) {
    final code = (value ?? '').trim().toLowerCase();
    switch (code) {
      case 'hi':
      case 'mr':
      case 'en':
        return code;
      default:
        return 'en';
    }
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    final lang = normalizeLanguageCode(locale.languageCode);
    final translated =
        _localizedValues[lang]?[key] ?? _localizedValues['en']?[key] ?? key;

    if (params.isEmpty) return translated;
    var output = translated;
    for (final entry in params.entries) {
      output = output.replaceAll('{${entry.key}}', entry.value);
    }
    return output;
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app.name': 'TerraCart',
      'common.save': 'Save',
      'common.cancel': 'Cancel',
      'common.logout': 'Logout',
      'common.dark': 'Dark',
      'common.light': 'Light',
      'common.settings': 'Settings',
      'common.language': 'Language',
      'common.version': 'Version {version}',
      'common.dashboard': 'Dashboard',
      'common.orders': 'Orders',
      'common.tables': 'Tables',
      'common.requests': 'Requests',
      'common.inventory': 'Inventory',
      'common.payments': 'Payments',
      'common.employees': 'Employees',
      'common.kot': 'KOT',
      'common.staff_member': 'Staff Member',
      'role.waiter': 'WAITER',
      'role.cook': 'COOK',
      'role.captain': 'CAPTAIN',
      'role.manager': 'MANAGER',
      'nav.voice_listening': 'Listening for voice commands...',
      'settings.personal_information': 'Personal Information',
      'settings.work': 'Work',
      'settings.daily_checklists': 'Daily Checklists',
      'settings.tasks': 'Tasks',
      'settings.work_schedule': 'Work Schedule',
      'settings.apply_leave': 'Apply Leave',
      'settings.choose_dates_reason': 'Choose dates and reason',
      'settings.attendance': 'Attendance',
      'settings.emergency_contacts': 'Emergency Contacts',
      'settings.manager': 'Manager',
      'settings.team_attendance': 'Team Attendance',
      'settings.manage_checkin_checkout': 'Manage check-in/check-out',
      'settings.printer': 'Printer',
      'settings.printer_configuration': 'Printer Configuration',
      'settings.printer_subtitle': 'KOT & Bill printer IP and port',
      'settings.compliance': 'Compliance',
      'settings.compliance_subtitle':
          'View compliance items & expiring documents',
      'settings.accessibility': 'Accessibility',
      'settings.accessibility_subtitle':
          'Deaf mode, visual alerts, vibration & more',
      'settings.notifications': 'Notifications',
      'settings.theme': 'Theme',
      'settings.support': 'Support',
      'settings.help_faq': 'Help & FAQ',
      'settings.contact_support': 'Contact Support',
      'settings.about_app': 'About App',
      'settings.logout_title': 'Logout',
      'settings.logout_message': 'Are you sure you want to logout?',
      'language.title': 'Language',
      'language.select_language': 'Select Language',
      'language.choose_preferred': 'Choose your preferred language',
      'language.save_language': 'Save Language',
      'language.changed_to': 'Language changed to {language}',
      'language.english': 'English',
      'language.hindi': 'Hindi',
      'language.marathi': 'Marathi',
      'language.native.english': 'English',
      'language.native.hindi': 'हिंदी',
      'language.native.marathi': 'मराठी',
      'about.title': 'About App',
      'about.latest_update': 'Latest Update',
      'about.checking_latest': 'Checking latest update...',
      'about.latest_version': 'Latest update: v{version}',
      'about.features': 'Features',
      'about.features_list':
          'Order management\nTable management\nInventory and waste tracking\nAttendance and task management',
      'about.developer': 'Developer',
      'about.developer_name': 'Ai Ally Pvt Ltd',
      'about.copyright': 'Copyright',
      'about.copyright_value': 'TerraCart.in copyright 2026',
      'about.license': 'License',
      'about.license_value': 'Proprietary',
      'about.built_for_accessibility':
          'Built for accessible restaurant operations.',
      'about.version_build': 'Version {version} (Build {build})',
      'contact.title': 'Contact Support',
      'contact.header_title': 'We are here to help',
      'contact.header_subtitle':
          'Choose a quick contact option or send a detailed message.',
      'contact.quick_contact': 'Quick Contact',
      'contact.call_support': 'Call Support',
      'contact.email_support': 'Email Support',
      'contact.call': 'Call',
      'contact.write': 'Write',
      'contact.support_hours': 'Support hours',
      'contact.support_hours_value': 'Mon-Sat, 9:00 AM - 7:00 PM',
      'contact.send_us_message': 'Send Us a Message',
      'contact.send_message': 'Send Message',
      'contact.your_name': 'Your Name *',
      'contact.your_email': 'Your Email *',
      'contact.subject': 'Subject *',
      'contact.message': 'Message *',
      'contact.name_required': 'Name is required',
      'contact.email_required': 'Email is required',
      'contact.email_invalid': 'Enter a valid email',
      'contact.subject_required': 'Subject is required',
      'contact.message_required': 'Message is required',
      'contact.validation_error':
          'Please fill in all required fields correctly.',
      'contact.opening_email': 'Opening your email app...',
      'contact.email_client_error': 'Could not launch email client',
      'contact.phone_error': 'Could not make phone call',
      'contact.default_subject': 'Support Request',
      'help.title': 'Help & FAQ',
      'help.header_title': 'Frequently Asked Questions',
      'help.header_subtitle':
          'Find quick answers for common tasks in TerraCart.',
      'help.need_more_help': 'Need more help? Contact support',
      'help.search_hint': 'Search questions or answers',
      'help.no_match': 'No FAQ matched your search.',
      'faq.q1': 'How do I check in for my shift?',
      'faq.a1':
          'Go to the Dashboard and tap the attendance card, or open Settings > Attendance. Tap "Check In" to start your shift.',
      'faq.q2': 'How do I create a new order?',
      'faq.a2':
          'Open Orders, tap the "+" or "New Order" button, select table/items, then tap "Create Order".',
      'faq.q3': 'How do I update my work schedule?',
      'faq.a3':
          'Go to Settings > Work Schedule, set your days and times, and tap "Save Schedule".',
      'faq.q4': 'How do I add emergency contacts?',
      'faq.a4':
          'Open Settings > Emergency Contacts, tap "+", fill details, then tap "Save Contacts".',
      'faq.q5': 'What if I forget to check out?',
      'faq.a5':
          'Contact your manager/admin to update the attendance record manually.',
      'faq.q6': 'How do I view my attendance history?',
      'faq.a6':
          'Open Settings > Attendance and use filters like Weekly, Monthly, or Custom range.',
      'faq.q7': 'How do I complete a task?',
      'faq.a7':
          'Go to Checklists, open the task menu (3 dots), then select "Mark as Completed".',
      'faq.q8': 'How do I scan a table QR code?',
      'faq.a8':
          'In Orders, tap the QR scanner and point the camera at the table QR code. The table is auto-selected.',
    },
    'hi': {
      'app.name': 'टेराकार्ट',
      'common.save': 'सेव करें',
      'common.cancel': 'रद्द करें',
      'common.logout': 'लॉगआउट',
      'common.dark': 'डार्क',
      'common.light': 'लाइट',
      'common.settings': 'सेटिंग्स',
      'common.language': 'भाषा',
      'common.version': 'संस्करण {version}',
      'common.dashboard': 'डैशबोर्ड',
      'common.orders': 'ऑर्डर',
      'common.tables': 'टेबल',
      'common.requests': 'अनुरोध',
      'common.inventory': 'इन्वेंटरी',
      'common.payments': 'भुगतान',
      'common.employees': 'कर्मचारी',
      'common.kot': 'KOT',
      'common.staff_member': 'स्टाफ सदस्य',
      'role.waiter': 'वेटर',
      'role.cook': 'कुक',
      'role.captain': 'कैप्टन',
      'role.manager': 'मैनेजर',
      'nav.voice_listening': 'वॉइस कमांड सुने जा रहे हैं...',
      'settings.personal_information': 'व्यक्तिगत जानकारी',
      'settings.work': 'कार्य',
      'settings.daily_checklists': 'दैनिक चेकलिस्ट',
      'settings.tasks': 'कार्य',
      'settings.work_schedule': 'कार्य समय-सारणी',
      'settings.apply_leave': 'छुट्टी के लिए आवेदन',
      'settings.choose_dates_reason': 'तिथि और कारण चुनें',
      'settings.attendance': 'उपस्थिति',
      'settings.emergency_contacts': 'आपातकालीन संपर्क',
      'settings.manager': 'मैनेजर',
      'settings.team_attendance': 'टीम उपस्थिति',
      'settings.manage_checkin_checkout': 'चेक-इन/चेक-आउट प्रबंधित करें',
      'settings.printer': 'प्रिंटर',
      'settings.printer_configuration': 'प्रिंटर कॉन्फ़िगरेशन',
      'settings.printer_subtitle': 'KOT और बिल प्रिंटर IP और पोर्ट',
      'settings.compliance': 'कंप्लायंस',
      'settings.compliance_subtitle':
          'कंप्लायंस आइटम और समाप्त होने वाले दस्तावेज़ देखें',
      'settings.accessibility': 'सुलभता',
      'settings.accessibility_subtitle':
          'डेफ मोड, विज़ुअल अलर्ट, वाइब्रेशन और अधिक',
      'settings.notifications': 'सूचनाएं',
      'settings.theme': 'थीम',
      'settings.support': 'सहायता',
      'settings.help_faq': 'सहायता और FAQ',
      'settings.contact_support': 'सपोर्ट से संपर्क करें',
      'settings.about_app': 'ऐप के बारे में',
      'settings.logout_title': 'लॉगआउट',
      'settings.logout_message': 'क्या आप वाकई लॉगआउट करना चाहते हैं?',
      'language.title': 'भाषा',
      'language.select_language': 'भाषा चुनें',
      'language.choose_preferred': 'अपनी पसंदीदा भाषा चुनें',
      'language.save_language': 'भाषा सेव करें',
      'language.changed_to': 'भाषा {language} में बदल दी गई',
      'language.english': 'अंग्रेज़ी',
      'language.hindi': 'हिंदी',
      'language.marathi': 'मराठी',
      'language.native.english': 'English',
      'language.native.hindi': 'हिंदी',
      'language.native.marathi': 'मराठी',
      'about.title': 'ऐप के बारे में',
      'about.latest_update': 'नवीनतम अपडेट',
      'about.checking_latest': 'नवीनतम अपडेट जांचा जा रहा है...',
      'about.latest_version': 'नवीनतम अपडेट: v{version}',
      'about.features': 'विशेषताएं',
      'about.features_list':
          'ऑर्डर प्रबंधन\nटेबल प्रबंधन\nइन्वेंटरी और वेस्ट ट्रैकिंग\nउपस्थिति और कार्य प्रबंधन',
      'about.developer': 'डेवलपर',
      'about.developer_name': 'Ai Ally Pvt Ltd',
      'about.copyright': 'कॉपीराइट',
      'about.copyright_value': 'TerraCart.in कॉपीराइट 2026',
      'about.license': 'लाइसेंस',
      'about.license_value': 'स्वामित्वाधीन',
      'about.built_for_accessibility':
          'सुलभ रेस्टोरेंट संचालन के लिए बनाया गया।',
      'about.version_build': 'संस्करण {version} (बिल्ड {build})',
      'contact.title': 'सपोर्ट से संपर्क करें',
      'contact.header_title': 'हम मदद के लिए यहाँ हैं',
      'contact.header_subtitle':
          'त्वरित संपर्क विकल्प चुनें या विस्तृत संदेश भेजें।',
      'contact.quick_contact': 'त्वरित संपर्क',
      'contact.call_support': 'सपोर्ट को कॉल करें',
      'contact.email_support': 'सपोर्ट को ईमेल करें',
      'contact.call': 'कॉल',
      'contact.write': 'लिखें',
      'contact.support_hours': 'सपोर्ट समय',
      'contact.support_hours_value': 'सोम-शनि, सुबह 9:00 - शाम 7:00',
      'contact.send_us_message': 'हमें संदेश भेजें',
      'contact.send_message': 'संदेश भेजें',
      'contact.your_name': 'आपका नाम *',
      'contact.your_email': 'आपका ईमेल *',
      'contact.subject': 'विषय *',
      'contact.message': 'संदेश *',
      'contact.name_required': 'नाम आवश्यक है',
      'contact.email_required': 'ईमेल आवश्यक है',
      'contact.email_invalid': 'वैध ईमेल दर्ज करें',
      'contact.subject_required': 'विषय आवश्यक है',
      'contact.message_required': 'संदेश आवश्यक है',
      'contact.validation_error': 'कृपया सभी आवश्यक फ़ील्ड सही भरें।',
      'contact.opening_email': 'आपका ईमेल ऐप खोला जा रहा है...',
      'contact.email_client_error': 'ईमेल क्लाइंट नहीं खुल सका',
      'contact.phone_error': 'फोन कॉल नहीं हो सकी',
      'contact.default_subject': 'सपोर्ट अनुरोध',
      'help.title': 'सहायता और FAQ',
      'help.header_title': 'अक्सर पूछे जाने वाले प्रश्न',
      'help.header_subtitle':
          'TerraCart में सामान्य कार्यों के त्वरित उत्तर पाएं।',
      'help.need_more_help': 'और मदद चाहिए? सपोर्ट से संपर्क करें',
      'help.search_hint': 'प्रश्न या उत्तर खोजें',
      'help.no_match': 'आपकी खोज से कोई FAQ मेल नहीं खाया।',
      'faq.q1': 'मैं अपनी शिफ्ट के लिए चेक-इन कैसे करूँ?',
      'faq.a1':
          'डैशबोर्ड पर जाएं और उपस्थिति कार्ड पर टैप करें, या सेटिंग्स > उपस्थिति खोलें। शिफ्ट शुरू करने के लिए "चेक इन" पर टैप करें।',
      'faq.q2': 'मैं नया ऑर्डर कैसे बनाऊँ?',
      'faq.a2':
          'ऑर्डर स्क्रीन खोलें, "+" या "नया ऑर्डर" पर टैप करें, टेबल/आइटम चुनें, फिर "ऑर्डर बनाएं" पर टैप करें।',
      'faq.q3': 'मैं अपना कार्य समय-सारणी कैसे अपडेट करूँ?',
      'faq.a3':
          'सेटिंग्स > कार्य समय-सारणी पर जाएं, दिन और समय सेट करें, और "सेव शेड्यूल" पर टैप करें।',
      'faq.q4': 'मैं आपातकालीन संपर्क कैसे जोड़ूँ?',
      'faq.a4':
          'सेटिंग्स > आपातकालीन संपर्क खोलें, "+" पर टैप करें, विवरण भरें, फिर "संपर्क सेव करें" पर टैप करें।',
      'faq.q5': 'यदि मैं चेक-आउट करना भूल जाऊँ तो क्या करूँ?',
      'faq.a5':
          'अपना रिकॉर्ड मैन्युअली अपडेट कराने के लिए मैनेजर/एडमिन से संपर्क करें।',
      'faq.q6': 'मैं अपनी उपस्थिति हिस्ट्री कैसे देखूँ?',
      'faq.a6':
          'सेटिंग्स > उपस्थिति खोलें और साप्ताहिक, मासिक या कस्टम रेंज जैसे फ़िल्टर उपयोग करें।',
      'faq.q7': 'मैं किसी कार्य को पूरा कैसे करूँ?',
      'faq.a7':
          'चेकलिस्ट स्क्रीन पर जाएं, कार्य मेनू (3 डॉट्स) खोलें, फिर "पूर्ण के रूप में चिह्नित करें" चुनें।',
      'faq.q8': 'मैं टेबल QR कोड कैसे स्कैन करूँ?',
      'faq.a8':
          'ऑर्डर स्क्रीन में QR स्कैनर पर टैप करें और कैमरा टेबल QR कोड पर रखें। टेबल स्वतः चयनित हो जाएगी।',
    },
    'mr': {
      'app.name': 'टेराकार्ट',
      'common.save': 'जतन करा',
      'common.cancel': 'रद्द करा',
      'common.logout': 'लॉगआउट',
      'common.dark': 'डार्क',
      'common.light': 'लाइट',
      'common.settings': 'सेटिंग्ज',
      'common.language': 'भाषा',
      'common.version': 'आवृत्ती {version}',
      'common.dashboard': 'डॅशबोर्ड',
      'common.orders': 'ऑर्डर्स',
      'common.tables': 'टेबल्स',
      'common.requests': 'विनंत्या',
      'common.inventory': 'इन्व्हेंटरी',
      'common.payments': 'देयके',
      'common.employees': 'कर्मचारी',
      'common.kot': 'KOT',
      'common.staff_member': 'स्टाफ सदस्य',
      'role.waiter': 'वेटर',
      'role.cook': 'कुक',
      'role.captain': 'कॅप्टन',
      'role.manager': 'मॅनेजर',
      'nav.voice_listening': 'व्हॉइस कमांड ऐकले जात आहेत...',
      'settings.personal_information': 'वैयक्तिक माहिती',
      'settings.work': 'काम',
      'settings.daily_checklists': 'दैनिक चेकलिस्ट',
      'settings.tasks': 'कामे',
      'settings.work_schedule': 'कामाचे वेळापत्रक',
      'settings.apply_leave': 'रजा अर्ज',
      'settings.choose_dates_reason': 'दिनांक आणि कारण निवडा',
      'settings.attendance': 'हजेरी',
      'settings.emergency_contacts': 'आपत्कालीन संपर्क',
      'settings.manager': 'मॅनेजर',
      'settings.team_attendance': 'टीम हजेरी',
      'settings.manage_checkin_checkout': 'चेक-इन/चेक-आउट व्यवस्थापित करा',
      'settings.printer': 'प्रिंटर',
      'settings.printer_configuration': 'प्रिंटर कॉन्फिगरेशन',
      'settings.printer_subtitle': 'KOT आणि बिल प्रिंटर IP आणि पोर्ट',
      'settings.compliance': 'अनुपालन',
      'settings.compliance_subtitle':
          'अनुपालन आयटम आणि कालबाह्य होणारी कागदपत्रे पहा',
      'settings.accessibility': 'सुलभता',
      'settings.accessibility_subtitle':
          'डेफ मोड, दृश्य सूचना, व्हायब्रेशन आणि अधिक',
      'settings.notifications': 'सूचना',
      'settings.theme': 'थीम',
      'settings.support': 'सपोर्ट',
      'settings.help_faq': 'मदत आणि FAQ',
      'settings.contact_support': 'सपोर्टशी संपर्क',
      'settings.about_app': 'अॅपबद्दल',
      'settings.logout_title': 'लॉगआउट',
      'settings.logout_message': 'तुम्हाला नक्की लॉगआउट करायचे आहे का?',
      'language.title': 'भाषा',
      'language.select_language': 'भाषा निवडा',
      'language.choose_preferred': 'तुमची पसंतीची भाषा निवडा',
      'language.save_language': 'भाषा जतन करा',
      'language.changed_to': 'भाषा {language} मध्ये बदलली',
      'language.english': 'इंग्रजी',
      'language.hindi': 'हिंदी',
      'language.marathi': 'मराठी',
      'language.native.english': 'English',
      'language.native.hindi': 'हिंदी',
      'language.native.marathi': 'मराठी',
      'about.title': 'अॅपबद्दल',
      'about.latest_update': 'नवीनतम अपडेट',
      'about.checking_latest': 'नवीनतम अपडेट तपासत आहे...',
      'about.latest_version': 'नवीनतम अपडेट: v{version}',
      'about.features': 'वैशिष्ट्ये',
      'about.features_list':
          'ऑर्डर व्यवस्थापन\nटेबल व्यवस्थापन\nइन्व्हेंटरी आणि वेस्ट ट्रॅकिंग\nहजेरी आणि काम व्यवस्थापन',
      'about.developer': 'डेव्हलपर',
      'about.developer_name': 'Ai Ally Pvt Ltd',
      'about.copyright': 'कॉपीराइट',
      'about.copyright_value': 'TerraCart.in कॉपीराइट 2026',
      'about.license': 'परवाना',
      'about.license_value': 'मालकी हक्क',
      'about.built_for_accessibility':
          'सुलभ रेस्टॉरंट ऑपरेशन्ससाठी तयार केलेले.',
      'about.version_build': 'आवृत्ती {version} (बिल्ड {build})',
      'contact.title': 'सपोर्टशी संपर्क',
      'contact.header_title': 'आम्ही मदतीसाठी आहोत',
      'contact.header_subtitle':
          'त्वरित संपर्क पर्याय निवडा किंवा सविस्तर संदेश पाठवा.',
      'contact.quick_contact': 'त्वरित संपर्क',
      'contact.call_support': 'सपोर्टला कॉल करा',
      'contact.email_support': 'सपोर्टला ईमेल करा',
      'contact.call': 'कॉल',
      'contact.write': 'लिहा',
      'contact.support_hours': 'सपोर्ट वेळ',
      'contact.support_hours_value': 'सोम-शनि, सकाळी 9:00 - सायं 7:00',
      'contact.send_us_message': 'आम्हाला संदेश पाठवा',
      'contact.send_message': 'संदेश पाठवा',
      'contact.your_name': 'तुमचे नाव *',
      'contact.your_email': 'तुमचा ईमेल *',
      'contact.subject': 'विषय *',
      'contact.message': 'संदेश *',
      'contact.name_required': 'नाव आवश्यक आहे',
      'contact.email_required': 'ईमेल आवश्यक आहे',
      'contact.email_invalid': 'वैध ईमेल टाका',
      'contact.subject_required': 'विषय आवश्यक आहे',
      'contact.message_required': 'संदेश आवश्यक आहे',
      'contact.validation_error': 'कृपया सर्व आवश्यक फील्ड योग्यरीत्या भरा.',
      'contact.opening_email': 'तुमचा ईमेल अॅप उघडत आहे...',
      'contact.email_client_error': 'ईमेल क्लायंट उघडता आला नाही',
      'contact.phone_error': 'फोन कॉल करता आला नाही',
      'contact.default_subject': 'सपोर्ट विनंती',
      'help.title': 'मदत आणि FAQ',
      'help.header_title': 'वारंवार विचारले जाणारे प्रश्न',
      'help.header_subtitle':
          'TerraCart मधील सामान्य कामांसाठी झटपट उत्तरे मिळवा.',
      'help.need_more_help': 'अजून मदत हवी आहे? सपोर्टशी संपर्क करा',
      'help.search_hint': 'प्रश्न किंवा उत्तरे शोधा',
      'help.no_match': 'तुमच्या शोधाशी कोणतेही FAQ जुळले नाही.',
      'faq.q1': 'मी माझ्या शिफ्टसाठी चेक-इन कसे करू?',
      'faq.a1':
          'डॅशबोर्डवर जा आणि हजेरी कार्डवर टॅप करा, किंवा सेटिंग्ज > हजेरी उघडा. शिफ्ट सुरू करण्यासाठी "Check In" वर टॅप करा.',
      'faq.q2': 'मी नवीन ऑर्डर कशी तयार करू?',
      'faq.a2':
          'ऑर्डर्स उघडा, "+" किंवा "New Order" वर टॅप करा, टेबल/आयटम निवडा आणि "Create Order" वर टॅप करा.',
      'faq.q3': 'मी माझे कामाचे वेळापत्रक कसे अपडेट करू?',
      'faq.a3':
          'सेटिंग्ज > कामाचे वेळापत्रक येथे जा, दिवस आणि वेळ सेट करा, आणि "Save Schedule" वर टॅप करा.',
      'faq.q4': 'मी आपत्कालीन संपर्क कसे जोडू?',
      'faq.a4':
          'सेटिंग्ज > आपत्कालीन संपर्क उघडा, "+" वर टॅप करा, तपशील भरा आणि "Save Contacts" वर टॅप करा.',
      'faq.q5': 'मी चेक-आउट करायला विसरलो तर काय करावे?',
      'faq.a5':
          'रेकॉर्ड मॅन्युअली अपडेट करण्यासाठी मॅनेजर/अॅडमिनशी संपर्क करा.',
      'faq.q6': 'मी माझी हजेरी हिस्टरी कशी पाहू?',
      'faq.a6':
          'सेटिंग्ज > हजेरी उघडा आणि Weekly, Monthly किंवा Custom range सारखे फिल्टर्स वापरा.',
      'faq.q7': 'मी एखादे काम पूर्ण कसे करू?',
      'faq.a7':
          'चेकलिस्ट स्क्रीनवर जा, कामाचे मेनू (3 dots) उघडा आणि "Mark as Completed" निवडा.',
      'faq.q8': 'मी टेबल QR कोड कसा स्कॅन करू?',
      'faq.a8':
          'ऑर्डर स्क्रीनमध्ये QR स्कॅनरवर टॅप करा आणि कॅमेरा टेबल QR कोडकडे ठेवा. टेबल आपोआप निवडले जाईल.',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
        (supported) => supported.languageCode == locale.languageCode,
      );

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String tr(String key, {Map<String, String> params = const {}}) {
    return l10n.tr(key, params: params);
  }
}
