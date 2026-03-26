class OrderStatusUtils {
  static const String statusNew = 'NEW';
  static const String statusPreparing = 'PREPARING';
  static const String statusReady = 'READY';
  static const String statusServed = 'SERVED';
  // Backward compatibility for existing references.
  static const String statusCompleted = statusServed;

  static const String paymentPending = 'PENDING';
  static const String paymentPaid = 'PAID';

  static const Set<String> employeeHiddenStatuses = {'served', 'completed'};
  static const Set<String> hiddenTakeawayStatuses = <String>{};

  static String normalizeStatus(String? status) {
    final token = (status ?? '')
        .trim()
        .toUpperCase()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (token.isEmpty) return statusNew;
    if (token == 'NEW' ||
        token == 'PENDING' ||
        token == 'CONFIRMED' ||
        token == 'ACCEPT' ||
        token == 'ACCEPTED') {
      return statusNew;
    }
    if (token == 'PREPARING' ||
        token == 'BEING PREPARED' ||
        token == 'BEINGPREPARED') {
      return statusPreparing;
    }
    if (token == 'READY') return statusReady;
    if (token == 'COMPLETED' ||
        token == 'SERVED' ||
        token == 'FINALIZED' ||
        token == 'PAID' ||
        token == 'CANCELLED' ||
        token == 'CANCELED' ||
        token == 'RETURNED' ||
        token == 'REJECTED' ||
        token == 'EXIT' ||
        token == 'CLOSED') {
      return statusServed;
    }
    return statusNew;
  }

  static String normalizePaymentStatus(
    String? paymentStatus, {
    String? status,
    bool isPaid = false,
  }) {
    final token = (paymentStatus ?? '').trim().toUpperCase();
    if (token == paymentPaid || isPaid) return paymentPaid;
    if ((status ?? '').trim().toUpperCase() == paymentPaid) {
      return paymentPaid;
    }
    return paymentPending;
  }

  static bool isDineInServiceType(String? serviceType) {
    return (serviceType ?? '').trim().toUpperCase() == 'DINE_IN';
  }

  static bool isTakeawayLikeServiceType(String? serviceType) {
    final normalized = (serviceType ?? '').trim().toUpperCase();
    return normalized == 'TAKEAWAY' ||
        normalized == 'PICKUP' ||
        normalized == 'DELIVERY';
  }

  static bool isTakeawayLikeOrder({
    String? serviceType,
    String? orderType,
  }) {
    return isTakeawayLikeServiceType(serviceType) ||
        isTakeawayLikeServiceType(orderType);
  }

  static String normalizePaymentMode(String? paymentMode) {
    final token = (paymentMode ?? '').trim().toUpperCase();
    if (token == 'COD') return 'CASH';
    return token;
  }

  static String normalizeOfficePaymentMode(String? officePaymentMode) {
    final token = (officePaymentMode ?? '').trim().toUpperCase();
    if (token == 'ONLINE' || token == 'COD' || token == 'BOTH') {
      return token;
    }
    return '';
  }

  static bool isCashOnDeliveryOrder({
    String? paymentMode,
    String? officePaymentMode,
  }) {
    if (normalizePaymentMode(paymentMode) == 'CASH') {
      return true;
    }
    return normalizeOfficePaymentMode(officePaymentMode) == 'COD';
  }

  static bool isPickupOrDeliveryOrder({
    String? serviceType,
    String? orderType,
  }) {
    final normalizedServiceType = (serviceType ?? '').trim().toUpperCase();
    final normalizedOrderType = (orderType ?? '').trim().toUpperCase();
    return normalizedServiceType == 'PICKUP' ||
        normalizedServiceType == 'DELIVERY' ||
        normalizedOrderType == 'PICKUP' ||
        normalizedOrderType == 'DELIVERY';
  }

  static bool requiresPaymentBeforeProceeding({
    bool paymentRequiredBeforeProceeding = false,
    String? sourceQrType,
    String? officePaymentMode,
    String? serviceType,
    String? orderType,
  }) {
    final isOfficeOrder = (sourceQrType ?? '').trim().toUpperCase() == 'OFFICE';
    if (isOfficeOrder) {
      // Business rule: OFFICE QR orders are prepaid-only.
      return true;
    }

    final normalizedServiceType = (serviceType ?? '').trim().toUpperCase();
    if (normalizedServiceType == 'DINE_IN') {
      // Dine-in is always counter/COD flow.
      return false;
    }

    if (paymentRequiredBeforeProceeding) return true;

    return isPickupOrDeliveryOrder(
      serviceType: serviceType,
      orderType: orderType,
    );
  }

  static bool isSettled({
    required String status,
    String? paymentStatus,
    bool isPaid = false,
  }) {
    final normalizedStatus = normalizeStatus(status);
    final normalizedPaymentStatus = normalizePaymentStatus(
      paymentStatus,
      status: status,
      isPaid: isPaid,
    );
    return normalizedStatus == statusServed &&
        normalizedPaymentStatus == paymentPaid;
  }

  static bool shouldShowForEmployees({
    required String status,
    String? paymentStatus,
    bool isPaid = false,
    String? paymentMode,
    String? officePaymentMode,
    bool paymentRequiredBeforeProceeding = false,
    String? sourceQrType,
    String? serviceType,
    String? orderType,
  }) {
    if (isSettled(
      status: status,
      paymentStatus: paymentStatus,
      isPaid: isPaid,
    )) {
      return false;
    }

    final normalizedPaymentStatus = normalizePaymentStatus(
      paymentStatus,
      status: status,
      isPaid: isPaid,
    );
    final isCodOrder = isCashOnDeliveryOrder(
      paymentMode: paymentMode,
      officePaymentMode: officePaymentMode,
    );
    final waitsForPayment = requiresPaymentBeforeProceeding(
      paymentRequiredBeforeProceeding: paymentRequiredBeforeProceeding,
      sourceQrType: sourceQrType,
      officePaymentMode: officePaymentMode,
      serviceType: serviceType,
      orderType: orderType,
    );

    if (waitsForPayment &&
        normalizedPaymentStatus != paymentPaid &&
        !isCodOrder) {
      return false;
    }

    return true;
  }
}
