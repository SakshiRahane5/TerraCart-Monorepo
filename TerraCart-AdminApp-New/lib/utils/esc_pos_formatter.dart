import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:intl/intl.dart';

/// Generates compact ESC/POS bytes for KOT and Bill printing.
class EscPosFormatter {
  static double _toNum(dynamic v, double def) {
    if (v == null) return def;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? def;
    return def;
  }

  static String _resolveOrderNote(
    Map<String, dynamic> order,
    Map<String, dynamic> kot,
  ) {
    final candidates = <dynamic>[
      order['specialInstructions'],
      order['specialInstruction'],
      order['orderNote'],
      order['note'],
      order['notes'],
      kot['specialInstructions'],
      kot['note'],
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString() ?? '';
      if (text.trim().isNotEmpty) return text;
    }
    return '';
  }

  static String _readConfigText(
    Map<String, dynamic>? printerConfig,
    String key, {
    String fallback = '',
  }) {
    final raw = printerConfig?[key];
    if (raw == null) return fallback;
    final text = raw.toString().trim();
    if (text.isEmpty) return fallback;
    return text;
  }

  static bool _readConfigBool(
    Map<String, dynamic>? printerConfig,
    String key, {
    bool fallback = true,
  }) {
    final raw = printerConfig?[key];
    if (raw is bool) return raw;
    if (raw is String) {
      final value = raw.trim().toLowerCase();
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return fallback;
  }

  static bool _isTakeawayLikeOrder(Map<String, dynamic> order) {
    final serviceType =
        order['serviceType']?.toString().trim().toUpperCase() ?? '';
    final orderType = order['orderType']?.toString().trim().toUpperCase() ?? '';
    if (serviceType == 'DINE_IN') return false;
    if (serviceType == 'TAKEAWAY' ||
        serviceType == 'PICKUP' ||
        serviceType == 'DELIVERY') {
      return true;
    }
    if (serviceType.isEmpty) {
      return orderType == 'PICKUP' ||
          orderType == 'DELIVERY' ||
          orderType == 'TAKEAWAY';
    }
    return false;
  }

  static String _normalizeMultilineNote(String value) {
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static void _addLine(
    List<int> bytes,
    Generator generator,
    String text, {
    required PosAlign align,
    bool bold = false,
  }) {
    bytes.addAll(
      generator.text(
        text,
        styles: PosStyles(
          align: align,
          bold: bold,
        ),
      ),
    );
  }

  static PosAlign _readLineAlign(dynamic value, PosAlign fallback) {
    final align = value?.toString().trim().toLowerCase() ?? '';
    if (align == 'center') return PosAlign.center;
    if (align == 'right') return PosAlign.right;
    if (align == 'left') return PosAlign.left;
    return fallback;
  }

  static String _normalizePaperWidth(String rawPaperWidth) {
    final normalized = rawPaperWidth.trim().toLowerCase();
    return normalized.contains('80') ? '80mm' : '58mm';
  }

  static int _resolveRowWidth(String paperWidth) {
    return paperWidth == '80mm' ? 42 : 32;
  }

  static String _separatorForWidth(int width) {
    final safeWidth = width > 0 ? width : 32;
    return List.filled(safeWidth, '-').join();
  }

  static String formatRow(String left, String right, int width) {
    final leftText = left.trim();
    final rightText = right.trim();
    if (width <= 0) {
      return '$leftText $rightText'.trim();
    }
    if (rightText.isEmpty) {
      return leftText.length <= width ? leftText : leftText.substring(0, width);
    }

    final availableLeft = width - rightText.length - 1;
    if (availableLeft <= 0) {
      return rightText.length <= width
          ? rightText
          : rightText.substring(rightText.length - width);
    }

    var safeLeft = leftText;
    if (safeLeft.length > availableLeft) {
      if (availableLeft > 2) {
        safeLeft = '${safeLeft.substring(0, availableLeft - 2)}..';
      } else {
        safeLeft = safeLeft.substring(0, availableLeft);
      }
    }

    final gap = width - safeLeft.length - rightText.length;
    final spacing = ' ' * (gap > 0 ? gap : 1);
    return '$safeLeft$spacing$rightText';
  }

  /// Render backend-provided compact KOT lines to ESC/POS bytes.
  static Future<List<int>> generateKotBytesFromTemplateLines(
    List<dynamic> lines, {
    Map<String, dynamic>? printerConfig,
    String paperWidth = '58mm',
  }) async {
    final profile = await CapabilityProfile.load();
    final normalizedPaper = paperWidth.trim().toLowerCase();
    final use80 = normalizedPaper.contains('80');
    final generator =
        Generator(use80 ? PaperSize.mm80 : PaperSize.mm58, profile);
    final rowWidth = use80 ? 42 : 32;
    final separator = _separatorForWidth(rowWidth);
    final bytes = <int>[];
    bytes.addAll(generator.reset());

    final centerAlign =
        _readConfigBool(printerConfig, 'centerAlign', fallback: true);
    final fallbackAlign = centerAlign ? PosAlign.center : PosAlign.left;

    for (final entry in lines) {
      final line = entry is Map ? Map<String, dynamic>.from(entry) : const {};
      final isSeparator = line['separator'] == true;
      var rawText = line['text']?.toString() ?? '';
      // Avoid printing "[object Object]" when backend sends object as text
      if (rawText == '[object Object]') rawText = '';
      final text = rawText.trim();
      final align = _readLineAlign(line['align'], fallbackAlign);
      final bold = line['bold'] == true;
      final indentValue = line['indent'];
      final indent = indentValue is num ? indentValue.toInt() : 0;
      final safeIndent = indent <= 0 ? '' : ' ' * (indent * 2);

      if (isSeparator) {
        _addLine(
          bytes,
          generator,
          text.isEmpty ? separator : text,
          align: align,
        );
        continue;
      }

      if (text.isEmpty) {
        _addLine(bytes, generator, ' ', align: align);
        continue;
      }

      _addLine(
        bytes,
        generator,
        '$safeIndent$text',
        align: align,
        bold: bold,
      );
    }

    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.cut());
    return bytes;
  }

  static List<Map<String, dynamic>> _buildInvoiceItems(
    Map<String, dynamic> order,
  ) {
    final Map<String, Map<String, dynamic>> aggregated = {};

    void addLine({
      required String name,
      required int quantity,
      required double unitPriceRupees,
    }) {
      if (quantity <= 0 || unitPriceRupees < 0) return;
      final key = name.trim();
      if (key.isEmpty) return;

      final lineAmount = unitPriceRupees * quantity;
      final existing = aggregated[key];
      if (existing == null) {
        aggregated[key] = {
          'name': key,
          'quantity': quantity,
          'unitPrice': unitPriceRupees,
          'amount': lineAmount,
        };
        return;
      }

      existing['quantity'] = (existing['quantity'] as int) + quantity;
      existing['amount'] = (existing['amount'] as double) + lineAmount;
    }

    final kotLines = order['kotLines'] as List<dynamic>? ?? [];
    for (final kot in kotLines) {
      final kotMap = kot is Map ? Map<String, dynamic>.from(kot) : const {};
      final items = kotMap['items'] as List<dynamic>? ?? [];
      for (final item in items) {
        final itemMap = item is Map ? Map<String, dynamic>.from(item) : {};
        if (itemMap['returned'] == true) continue;

        final name = itemMap['name']?.toString() ?? 'Item';
        final quantity = _toNum(itemMap['quantity'], 0).toInt().clamp(0, 9999);
        final itemPriceRupees = _toNum(itemMap['price'], 0) / 100;
        addLine(
          name: name,
          quantity: quantity,
          unitPriceRupees: itemPriceRupees,
        );
      }
    }

    final selectedAddons = order['selectedAddons'] as List<dynamic>? ?? [];
    for (final addon in selectedAddons) {
      final addonMap = addon is Map ? Map<String, dynamic>.from(addon) : {};
      final name = addonMap['name']?.toString() ?? 'Add-on';
      final quantity = _toNum(addonMap['quantity'], 1).toInt().clamp(1, 9999);
      final unitPriceRupees = _toNum(addonMap['price'], 0);
      addLine(
        name: '(+) $name',
        quantity: quantity,
        unitPriceRupees: unitPriceRupees,
      );
    }

    return aggregated.values.toList(growable: false);
  }

  static Future<List<int>> generateKotBytes(
    Map<String, dynamic> order,
    Map<String, dynamic> kot,
    int kotIndex, {
    Map<String, dynamic>? printerConfig,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];
    bytes.addAll(generator.reset());

    final centerAlign =
        _readConfigBool(printerConfig, 'centerAlign', fallback: true);
    final lineAlign = centerAlign ? PosAlign.center : PosAlign.left;
    final businessName = _readConfigText(
      printerConfig,
      'businessName',
      fallback: 'TERRA CART',
    );
    final kotHeaderText = _readConfigText(printerConfig, 'kotHeaderText');

    final now = DateTime.now();
    final timeStr = DateFormat('dd MMM, hh:mm a').format(now);
    final isTakeawayLike = _isTakeawayLikeOrder(order);
    final orderId = (order['_id'] ?? order['id'] ?? '').toString();
    final orderRef = orderId.length > 8
        ? orderId.substring(orderId.length - 8).toUpperCase()
        : orderId.toUpperCase();
    final orderNote = _resolveOrderNote(order, kot);

    const rowWidth = 32;
    final separator = _separatorForWidth(rowWidth);
    final serviceLabel = isTakeawayLike ? 'TAKEAWAY' : 'DINE-IN';
    final rawKotNumber = kot['kotNumber'];
    final parsedKotNumber = rawKotNumber is num
        ? rawKotNumber.toInt()
        : int.tryParse(rawKotNumber?.toString() ?? '');
    final kotNumber = (parsedKotNumber != null && parsedKotNumber > 0)
        ? parsedKotNumber
        : kotIndex + 1;

    _addLine(
      bytes,
      generator,
      businessName,
      align: lineAlign,
      bold: true,
    );
    if (kotHeaderText.isNotEmpty) {
      for (final line in kotHeaderText.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        _addLine(
          bytes,
          generator,
          trimmed,
          align: lineAlign,
          bold: true,
        );
      }
    }

    _addLine(
      bytes,
      generator,
      'KOT #${kotNumber.toString().padLeft(2, '0')} $serviceLabel',
      align: lineAlign,
      bold: true,
    );
    _addLine(bytes, generator, timeStr, align: lineAlign);
    _addLine(bytes, generator, separator, align: lineAlign);

    final hasToken = isTakeawayLike && order['takeawayToken'] != null;
    final hasTable = !isTakeawayLike &&
        order['tableNumber'] != null &&
        order['tableNumber'].toString().trim().isNotEmpty;

    if (hasToken) {
      _addLine(
        bytes,
        generator,
        'Token: ${order['takeawayToken']}',
        align: lineAlign,
        bold: true,
      );
    } else if (hasTable) {
      _addLine(
        bytes,
        generator,
        'Table: ${order['tableNumber']}',
        align: lineAlign,
        bold: true,
      );
    }

    if (orderRef.isNotEmpty) {
      _addLine(bytes, generator, 'Ref: $orderRef', align: lineAlign);
    }

    if (isTakeawayLike) {
      final customerName = order['customerName']?.toString().trim() ?? '';
      final customerMobile = order['customerMobile']?.toString().trim() ?? '';
      if (customerName.isNotEmpty) {
        _addLine(bytes, generator, 'Customer: $customerName', align: lineAlign);
      }
      if (customerMobile.isNotEmpty) {
        _addLine(bytes, generator, 'Mobile: $customerMobile', align: lineAlign);
      }
    }

    if (orderNote.isNotEmpty) {
      final formattedNote = _normalizeMultilineNote(orderNote);
      _addLine(
        bytes,
        generator,
        'Note:',
        align: lineAlign,
        bold: true,
      );
      for (final line in formattedNote.split('\n')) {
        _addLine(
          bytes,
          generator,
          line.isEmpty ? ' ' : line,
          align: lineAlign,
          bold: true,
        );
      }
    }

    _addLine(bytes, generator, separator, align: lineAlign);

    final items = kot['items'] as List<dynamic>? ?? [];
    if (items.isEmpty) {
      _addLine(bytes, generator, 'No items', align: lineAlign);
    }
    for (final item in items) {
      final itemMap = item is Map ? Map<String, dynamic>.from(item) : {};
      final returned = itemMap['returned'] == true;
      final name = itemMap['name']?.toString() ?? '';
      final qty = _toNum(itemMap['quantity'], 0).toInt();

      if (returned) {
        final cancelledRow = formatRow('X $name', '${qty}x', rowWidth);
        _addLine(bytes, generator, cancelledRow, align: PosAlign.left);
        continue;
      }

      final itemRow = formatRow(name, '${qty}x', rowWidth);
      _addLine(
        bytes,
        generator,
        itemRow,
        align: PosAlign.left,
        bold: true,
      );

      final note = (itemMap['specialInstructions'] ?? itemMap['note'] ?? '')
          .toString()
          .trim();
      if (note.isNotEmpty) {
        _addLine(bytes, generator, '* $note', align: PosAlign.left);
      }

      final extras = itemMap['extras'] as List<dynamic>? ?? const [];
      if (extras.isNotEmpty) {
        final extraNames = extras
            .whereType<Map>()
            .map((extra) => extra['name']?.toString().trim() ?? '')
            .where((extraName) => extraName.isNotEmpty)
            .toList();
        if (extraNames.isNotEmpty) {
          _addLine(
            bytes,
            generator,
            '+ ${extraNames.join(', ')}',
            align: PosAlign.left,
          );
        }
      }
    }

    _addLine(bytes, generator, separator, align: lineAlign);
    final activeItems =
        items.where((i) => (i is Map ? i['returned'] : false) != true).toList();
    final totalQty = activeItems.fold<int>(0, (sum, i) {
      final qty = i is Map ? i['quantity'] : null;
      final n = qty is num ? qty.toInt().clamp(0, 999) : 0;
      return sum + n;
    });
    _addLine(
      bytes,
      generator,
      'Items: ${activeItems.length}  Qty: $totalQty',
      align: lineAlign,
      bold: true,
    );
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.cut());

    return bytes;
  }

  static Future<List<int>> generateBillBytes(
    Map<String, dynamic> order,
    String? paymentMethod, {
    Map<String, dynamic>? cartData,
    Map<String, dynamic>? printerConfig,
  }) async {
    final paperWidth =
        _normalizePaperWidth(_readConfigText(printerConfig, 'paperWidth'));
    final rowWidth = _resolveRowWidth(paperWidth);
    final profile = await CapabilityProfile.load();
    final generator =
        Generator(paperWidth == '80mm' ? PaperSize.mm80 : PaperSize.mm58, profile);
    final bytes = <int>[];
    bytes.addAll(generator.reset());

    final centerAlign =
        _readConfigBool(printerConfig, 'centerAlign', fallback: true);
    final lineAlign = centerAlign ? PosAlign.center : PosAlign.left;
    final businessName = _readConfigText(
      printerConfig,
      'businessName',
      fallback: 'TERRA CART',
    );
    final billHeaderText = _readConfigText(printerConfig, 'billHeaderText');

    final orderId = (order['_id'] ?? order['id'] ?? '').toString();
    final paidAt = order['paidAt'];
    final createdAt = order['createdAt'];
    DateTime orderDate = DateTime.now();
    if (paidAt != null) {
      orderDate = paidAt is DateTime
          ? paidAt
          : DateTime.tryParse(paidAt.toString()) ?? orderDate;
    } else if (createdAt != null) {
      orderDate = createdAt is DateTime
          ? createdAt
          : DateTime.tryParse(createdAt.toString()) ?? orderDate;
    }

    final dateStr = DateFormat('M/d/yyyy').format(orderDate);
    final isTakeawayLike = _isTakeawayLikeOrder(order);

    final tail = orderId.length >= 6
        ? orderId.substring(orderId.length - 6).toUpperCase()
        : orderId.toUpperCase();
    final shortDate = DateFormat('yyMMdd').format(orderDate);
    final shortTail = tail.length > 4 ? tail.substring(tail.length - 4) : tail;
    final invoiceNo = 'INV-$shortDate-$shortTail';

    String addressFrom(dynamic value) {
      if (value == null) return '';
      if (value is String) return value.trim();
      if (value is Map && value['fullAddress'] != null) {
        return value['fullAddress'].toString().trim();
      }
      if (value is Map && value['address'] != null) {
        return value['address'].toString().trim();
      }
      return value.toString().trim();
    }

    final cartLocation = addressFrom(cartData?['location']).isNotEmpty
        ? addressFrom(cartData?['location'])
        : addressFrom(cartData?['address']);
    final billAddress = cartLocation;

    _addLine(
      bytes,
      generator,
      businessName,
      align: lineAlign,
      bold: true,
    );
    if (billHeaderText.isNotEmpty) {
      for (final line in billHeaderText.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        _addLine(
          bytes,
          generator,
          trimmed,
          align: lineAlign,
          bold: true,
        );
      }
    }
    if (billAddress.isNotEmpty) {
      _addLine(bytes, generator, billAddress, align: lineAlign);
    }
    _addLine(bytes, generator, 'Invoice: $invoiceNo', align: lineAlign);
    _addLine(bytes, generator, 'Date: $dateStr', align: lineAlign);

    if (isTakeawayLike && order['takeawayToken'] != null) {
      _addLine(
        bytes,
        generator,
        'Token: ${order['takeawayToken']}',
        align: lineAlign,
      );
    } else if (!isTakeawayLike) {
      _addLine(
        bytes,
        generator,
        'Table: ${order['tableNumber'] ?? '-'}',
        align: lineAlign,
      );
    }

    if (isTakeawayLike) {
      final customerName = order['customerName']?.toString().trim() ?? '';
      final customerMobile = order['customerMobile']?.toString().trim() ?? '';
      if (customerName.isNotEmpty || customerMobile.isNotEmpty) {
        _addLine(
          bytes,
          generator,
          'Customer: $customerName $customerMobile'.trim(),
          align: lineAlign,
        );
      }
    }

    final separator = _separatorForWidth(rowWidth);
    _addLine(bytes, generator, separator, align: lineAlign);

    final invoiceItems = _buildInvoiceItems(order);
    if (invoiceItems.isEmpty) {
      _addLine(bytes, generator, 'No items', align: lineAlign);
    } else {
      for (final item in invoiceItems) {
        final name = item['name']?.toString() ?? '';
        final qty = _toNum(item['quantity'], 0).toInt().clamp(0, 9999);
        final price = _toNum(item['unitPrice'], 0);
        final lineTotal = _toNum(item['amount'], price * qty);
        final itemRow = formatRow(
          '$name x$qty',
          'Rs.${lineTotal.toStringAsFixed(2)}',
          rowWidth,
        );
        _addLine(
          bytes,
          generator,
          itemRow,
          align: PosAlign.left,
        );
      }

      final subtotal = invoiceItems.fold<double>(
        0.0,
        (sum, item) => sum + _toNum(item['amount'], 0),
      );
      final total = subtotal;

      _addLine(bytes, generator, separator, align: lineAlign);
      _addLine(
        bytes,
        generator,
        formatRow('Subtotal', 'Rs.${subtotal.toStringAsFixed(2)}', rowWidth),
        align: PosAlign.left,
      );
      _addLine(
        bytes,
        generator,
        formatRow('Total', 'Rs.${total.toStringAsFixed(2)}', rowWidth),
        align: PosAlign.left,
        bold: true,
      );
    }

    _addLine(
      bytes,
      generator,
      'Payment ${(paymentMethod ?? 'CASH').toUpperCase()}',
      align: lineAlign,
    );
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.cut());

    return bytes;
  }
}
