import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme/app_colors.dart';

class QRScannerScreen extends StatefulWidget {
  final Function(String) onScanComplete;

  const QRScannerScreen({
    super.key,
    required this.onScanComplete,
  });

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Delay initialization to ensure widget is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScanner();
    });
  }

  Future<void> _initializeScanner() async {
    try {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        returnImage: false,
      );

      // Wait a bit for the controller to be ready
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize camera: ${e.toString()}';
          _isInitialized = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture barcodeCapture) {
    if (_isProcessing || !mounted) return;

    final barcodes = barcodeCapture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    if (barcode.rawValue == null || barcode.rawValue!.isEmpty) return;

    setState(() => _isProcessing = true);

    // Stop the scanner
    _controller?.stop();

    // Extract the slug from the QR code
    // QR code might be a URL like: https://example.com/tables/abc123
    // or just the slug: abc123
    String? slug = _extractSlugFromQR(barcode.rawValue!);

    if (slug != null && slug.isNotEmpty) {
      // Call the callback with the slug (synchronously to avoid issues)
      try {
        widget.onScanComplete(slug);
      } catch (e) {
        // If callback fails, reset and show error
        if (mounted) {
          setState(() => _isProcessing = false);
          _controller?.start();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing QR code: ${e.toString()}'),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Close the scanner screen after a short delay
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    } else {
      // Invalid QR code
      setState(() => _isProcessing = false);
      _controller?.start();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Invalid table QR code. Please scan a valid table QR.'),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String? _extractSlugFromQR(String qrValue) {
    // Clean the input
    final cleaned = qrValue.trim();

    // Try to extract slug/tableId from query parameter.
    // Handles: ?table=... or ?tableId=...
    final queryParamPattern = RegExp(
      r'[?&](?:table|tableId)=([a-fA-F0-9_-]+)',
      caseSensitive: false,
    );
    final queryMatch = queryParamPattern.firstMatch(cleaned);
    if (queryMatch != null && queryMatch.group(1) != null) {
      return queryMatch.group(1);
    }

    // Try to extract slug from URL pattern: /tables/lookup/{slug} or /tables/{slug}
    // Also handle full URLs like https://example.com/tables/lookup/abc123
    final urlPattern =
        RegExp(r'(?:https?://[^/]+)?/tables/(?:lookup/)?([a-fA-F0-9_-]+)');
    final match = urlPattern.firstMatch(cleaned);
    if (match != null && match.group(1) != null) {
      return match.group(1);
    }

    // If it's just a hex slug (16 characters hex string from backend generateSlug)
    // Backend generates: crypto.randomBytes(8).toString("hex") = 16 hex characters
    final hexSlugPattern = RegExp(r'^[a-fA-F0-9]{16}$');
    if (hexSlugPattern.hasMatch(cleaned)) {
      return cleaned;
    }

    // Also accept any alphanumeric string (for backward compatibility)
    final slugPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
    if (slugPattern.hasMatch(cleaned) && cleaned.length >= 8) {
      return cleaned;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Scan Table QR Code'),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _errorMessage = null;
                    });
                    _initializeScanner();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Scan Table QR Code'),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    if (_controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Scan Table QR Code'),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Table QR Code'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller!,
            onDetect: _handleBarcode,
            fit: BoxFit.cover,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Camera Error: ${error.toString()}',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _errorMessage = null;
                            _isInitialized = false;
                          });
                          _controller?.dispose();
                          _initializeScanner();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Overlay with scanning area
          CustomPaint(
            painter: ScannerOverlay(),
            child: Container(),
          ),
          // Instructions
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Position the QR code within the frame',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isProcessing)
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    // Draw overlay with transparent center
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final centerWidth = size.width * 0.7;
    final centerHeight = size.width * 0.7;
    final centerX = (size.width - centerWidth) / 2;
    final centerY = (size.height - centerHeight) / 2 - 50;

    final centerRect =
        Rect.fromLTWH(centerX, centerY, centerWidth, centerHeight);
    final centerPath = Path()..addRect(centerRect);

    final overlayPath = Path.combine(
      PathOperation.difference,
      path,
      centerPath,
    );

    canvas.drawPath(overlayPath, paint);

    // Draw corner brackets
    final cornerPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final cornerLength = 30.0;

    // Top-left corner
    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX + cornerLength, centerY),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX, centerY + cornerLength),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(centerX + centerWidth, centerY),
      Offset(centerX + centerWidth - cornerLength, centerY),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX + centerWidth, centerY),
      Offset(centerX + centerWidth, centerY + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(centerX, centerY + centerHeight),
      Offset(centerX + cornerLength, centerY + centerHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY + centerHeight),
      Offset(centerX, centerY + centerHeight - cornerLength),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(centerX + centerWidth, centerY + centerHeight),
      Offset(centerX + centerWidth - cornerLength, centerY + centerHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX + centerWidth, centerY + centerHeight),
      Offset(centerX + centerWidth, centerY + centerHeight - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
