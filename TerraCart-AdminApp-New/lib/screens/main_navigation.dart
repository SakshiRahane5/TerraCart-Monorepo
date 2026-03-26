import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../providers/app_provider.dart';
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
          const OrdersScreen(),
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
            icon: const Icon(Icons.add_shopping_cart_outlined),
            activeIcon: const Icon(Icons.add_shopping_cart),
            label: context.tr('common.orders'),
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
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
          if (isVoiceEnabled)
            Positioned(
              right: 16,
              bottom: 100,
              child: FloatingActionButton(
                heroTag: 'voice_command_fab',
                mini: true,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('nav.voice_listening')),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.mic, color: Colors.white),
              ),
            ),
        ],
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
