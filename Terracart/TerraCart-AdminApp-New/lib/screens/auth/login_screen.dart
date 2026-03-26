import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/biometric_service.dart';
import '../../services/user_service.dart';
import '../../services/employee_service.dart';
import '../../utils/connection_test.dart';
import '../main_navigation.dart';
import '../accessibility/accessibility_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _attendanceService = AttendanceService();
  final _biometricService = BiometricService();
  final _userService = UserService();
  final _employeeService = EmployeeService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  String? _locationAddress;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
    _loadStoredCredentials();
  }

  Future<void> _checkBiometricAvailability() async {
    final isAvailable = await _biometricService.isBiometricsAvailable();
    final isEnabled = await _biometricService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _isBiometricAvailable = isAvailable;
        _isBiometricEnabled = isEnabled;
      });
    }
  }

  Future<void> _loadStoredCredentials() async {
    if (_isBiometricEnabled) {
      final credentials = await _biometricService.getStoredCredentials();
      if (mounted && credentials['email'] != null) {
        _emailController.text = credentials['email'] ?? '';
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    if (!mounted) return;

    final connectionResult = await ConnectionTest.testConnection();
    if (!(connectionResult['success'] == true)) {
      final message = connectionResult['message']?.toString() ?? '';
      final isHostUnreachable =
          message.toLowerCase().contains('no route to host') ||
              message.toLowerCase().contains('cannot reach server') ||
              message.toLowerCase().contains('network is unreachable');
      if (isHostUnreachable) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Server unreachable at ${ApiConfig.baseUrl}. Check backend binding, LAN IP, and firewall.',
              ),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    final appProvider = Provider.of<AppProvider>(context, listen: false);

    try {
      await appProvider.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      // Check if login was successful (no error message means success)
      if (appProvider.errorMessage == null && appProvider.isLoggedIn) {
        // Save credentials for biometric login
        await _biometricService.saveCredentials(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        // Fetch cart/cafe address
        await _fetchLocationAddress();
        final shouldShowModal = await _shouldShowAttendanceModal(appProvider);
        if (shouldShowModal) {
          _showAttendanceModal();
        } else {
          _navigateToHome();
        }
      } else {
        // Login failed - show error message
        setState(() => _isLoading = false);

        // Check if it's a restricted role error
        final errorMsg =
            appProvider.errorMessage ?? 'Login failed. Please try again.';
        if (errorMsg.contains('Access denied') ||
            errorMsg.contains('restricted')) {
          // Show popup dialog for restricted roles
          _showRestrictedRoleDialog(context, appProvider);
        } else {
          // Show regular error snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // Fallback error handling (shouldn't happen now, but keep for safety)
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appProvider.errorMessage ?? e.toString(),
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<bool> _shouldShowAttendanceModal(AppProvider appProvider) async {
    try {
      final attendanceList = await _attendanceService.getTodayAttendance();
      if (attendanceList.isEmpty) {
        return true;
      }

      final currentEmployeeId = appProvider.currentUser?.employeeId;
      Map<String, dynamic>? currentRecord;

      if (currentEmployeeId != null && currentEmployeeId.isNotEmpty) {
        for (final record in attendanceList) {
          final employeeValue = record['employeeId'];
          final employeeId = employeeValue is Map
              ? employeeValue['_id']?.toString()
              : employeeValue?.toString();
          if (employeeId == currentEmployeeId) {
            currentRecord = record;
            break;
          }
        }
      }

      currentRecord ??= attendanceList.first;
      return !_hasAlreadyCheckedIn(currentRecord);
    } catch (_) {
      return true;
    }
  }

  bool _hasAlreadyCheckedIn(Map<String, dynamic>? attendance) {
    if (attendance == null) {
      return false;
    }

    final status =
        attendance['attendanceStatus']?.toString().trim().toLowerCase() ?? '';
    final checkInStatus =
        attendance['checkInStatus']?.toString().trim().toLowerCase() ?? '';

    if (status == 'checked_in' ||
        status == 'on_break' ||
        status == 'checked_out' ||
        checkInStatus == 'checked_in' ||
        checkInStatus == 'checked_out') {
      return true;
    }

    final checkIn = attendance['checkIn'];
    if (checkIn is Map) {
      final time = checkIn['time']?.toString().trim();
      if (time != null && time.isNotEmpty) {
        return true;
      }
    }

    final checkInTime = attendance['checkInTime']?.toString().trim();
    if (checkInTime != null && checkInTime.isNotEmpty) {
      return true;
    }

    return false;
  }

  void _showAttendanceModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                size: 40,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Confirm Your Location',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your location will be recorded for attendance.\nPlease confirm you are at the work location.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.my_location, color: AppColors.info),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Location',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Text(
                          _locationAddress ?? 'Loading location...',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _navigateToHome());
                    },
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _navigateToHome());
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirm Attendance'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBiometricLogin() async {
    try {
      // Authenticate with biometrics
      final isAuthenticated = await _biometricService.authenticate(
        reason: 'Authenticate to login to Terra Card Staff App',
      );

      if (!isAuthenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Biometric authentication failed or cancelled'),
              backgroundColor: AppColors.error,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Get stored credentials
      final credentials = await _biometricService.getStoredCredentials();
      if (credentials['email'] == null || credentials['password'] == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No saved credentials found. Please login manually first.'),
              backgroundColor: AppColors.error,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Set loading state
      setState(() => _isLoading = true);

      if (!mounted) return;

      final appProvider = Provider.of<AppProvider>(context, listen: false);

      // Login with stored credentials
      await appProvider.login(
        email: credentials['email']!,
        password: credentials['password']!,
      );

      if (!mounted) return;

      // Check if login was successful
      if (appProvider.errorMessage == null && appProvider.isLoggedIn) {
        // Fetch cart/cafe address
        await _fetchLocationAddress();
        final shouldShowModal = await _shouldShowAttendanceModal(appProvider);
        if (shouldShowModal) {
          _showAttendanceModal();
        } else {
          _navigateToHome();
        }
      } else {
        // Login failed
        setState(() => _isLoading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appProvider.errorMessage ?? 'Login failed. Please try again.',
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Biometric login error: ${e.toString()}'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _fetchLocationAddress() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      String? cartId = appProvider.currentUser?.cartId;

      print('[LOGIN] Fetching location - Initial cartId from user: $cartId');
      print(
          '[LOGIN] Current user employeeId: ${appProvider.currentUser?.employeeId}');

      // If cartId is not in user object, try to get it from employee record
      if ((cartId == null || cartId.isEmpty) &&
          appProvider.currentUser?.employeeId != null) {
        try {
          final employeeId = appProvider.currentUser!.employeeId!;
          print('[LOGIN] Fetching employee record with ID: $employeeId');
          final employeeData =
              await _employeeService.getEmployeeById(employeeId);
          cartId = employeeData['cartId']?.toString() ??
              employeeData['cafeId']
                  ?.toString(); // Support both for backward compatibility

          print('[LOGIN] Fetched cartId from employee record: $cartId');
        } catch (e) {
          print('[LOGIN] Failed to fetch employee record: $e');
        }
      }

      if (cartId != null && cartId.isNotEmpty) {
        print('[LOGIN] Fetching cafe/cart data for cartId: $cartId');
        final cafeData = await _userService.getUserById(cartId);

        print(
            '[LOGIN] Cafe data received - address: ${cafeData['address']}, location: ${cafeData['location']}');

        // Prefer address, fallback to location
        final address = cafeData['address'] ?? cafeData['location'];

        print('[LOGIN] Final location address: $address');

        if (mounted) {
          setState(() {
            _locationAddress = address ?? 'Location not specified';
          });
        }
      } else {
        print('[LOGIN] No cartId found - cannot fetch location');
        if (mounted) {
          setState(() {
            _locationAddress = 'Location not specified';
          });
        }
      }
    } catch (e) {
      print('[LOGIN] Failed to fetch location address: $e');
      print('[LOGIN] Error details: ${e.toString()}');
      if (mounted) {
        setState(() {
          _locationAddress = 'Location not available';
        });
      }
    }
  }

  void _navigateToHome() {
    if (mounted) {
      setState(() => _isLoading = false);
    }
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    });
  }

  void _showRestrictedRoleDialog(
      BuildContext context, AppProvider appProvider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.block, color: AppColors.error),
            const SizedBox(width: 12),
            const Text('Access Restricted'),
          ],
        ),
        content: const Text(
          'Mobile app login is only available for waiter, cook, captain, and manager roles.\n\nPlease contact your administrator if you need access.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Logout the user
              await appProvider.logout();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome Back Text with Accessibility Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Welcome Back! 👋',
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ).animate().fadeIn().slideX(begin: -0.1),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AccessibilityScreen(),
                          ),
                        );
                      },
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.accessibility_new_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                    ).animate().fadeIn(),
                  ],
                ),

                const SizedBox(height: 8),

                Text(
                  'Sign in to continue to Terra Cart Staff App',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),

                const SizedBox(height: 40),

                // Logo
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.restaurant_menu_rounded,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                ).animate().scale(delay: 200.ms, curve: Curves.elasticOut),

                const SizedBox(height: 40),

                // Email Field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter your email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),

                const SizedBox(height: 16),

                // Password Field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),

                const SizedBox(height: 12),

                // Forgot Password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {},
                    child: Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('Sign In'),
                  ),
                ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),

                const SizedBox(height: 16),

                // Biometric Login
                if (_isBiometricAvailable && _isBiometricEnabled)
                  Center(
                    child: TextButton.icon(
                      onPressed: _isLoading ? null : _handleBiometricLogin,
                      icon: const Icon(Icons.fingerprint, size: 28),
                      label: const Text('Use Biometric Login'),
                    ),
                  ).animate().fadeIn(delay: 500.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
