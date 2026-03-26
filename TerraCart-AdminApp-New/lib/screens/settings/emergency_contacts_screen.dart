import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../services/user_service.dart';
import '../../core/exceptions/api_exception.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final UserService _userService = UserService();
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  
  // Store TextEditingControllers for each contact field
  final Map<int, Map<String, TextEditingController>> _controllers = {};

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    // Dispose all controllers
    for (var controllers in _controllers.values) {
      controllers.values.forEach((controller) => controller.dispose());
    }
    _controllers.clear();
    super.dispose();
  }

  // Initialize controllers for a contact at given index
  void _initializeControllers(int index) {
    if (!_controllers.containsKey(index) && index < _contacts.length) {
      final contact = _contacts[index];
      _controllers[index] = {
        'name': TextEditingController(text: contact['name']?.toString() ?? ''),
        'phone': TextEditingController(text: contact['phone']?.toString() ?? ''),
        'email': TextEditingController(text: contact['email']?.toString() ?? ''),
        'relationship': TextEditingController(text: contact['relationship']?.toString() ?? ''),
      };
    }
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final contacts = await _userService.getEmergencyContacts();
      if (mounted) {
        setState(() {
          // Dispose old controllers
          for (var controllers in _controllers.values) {
            controllers.values.forEach((controller) => controller.dispose());
          }
          _controllers.clear();
          
          // Ensure contacts are properly formatted
          _contacts = contacts.map((contact) {
            return {
              'name': contact['name']?.toString() ?? '',
              'phone': contact['phone']?.toString() ?? '',
              'email': contact['email']?.toString() ?? '',
              'relationship': contact['relationship']?.toString() ?? '',
              'isPrimary': contact['isPrimary'] == true || contact['isPrimary'] == 'true',
              'createdAt': contact['createdAt'],
              'updatedAt': contact['updatedAt'],
            };
          }).toList();
          
          // Initialize controllers for all contacts
          for (int i = 0; i < _contacts.length; i++) {
            _initializeControllers(i);
          }
          
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is ApiException ? e.message : 'Failed to load contacts';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveContacts() async {
    // Validate contacts before saving
    final validContacts = _contacts.where((contact) {
      final name = contact['name']?.toString().trim() ?? '';
      final phone = contact['phone']?.toString().trim() ?? '';
      return name.isNotEmpty && phone.isNotEmpty;
    }).toList();

    if (validContacts.isEmpty && _contacts.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in at least name and phone for one contact'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final savedContacts = await _userService.updateEmergencyContacts(validContacts);
      if (mounted) {
        setState(() {
          _contacts = savedContacts;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Emergency contacts saved successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        // Reload to ensure we have the latest data
        await _loadContacts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Failed to save contacts',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _addContact() {
    setState(() {
      final newIndex = _contacts.length;
      _contacts.add({
        'name': '',
        'phone': '',
        'email': '',
        'relationship': '',
        'isPrimary': _contacts.isEmpty, // First contact is primary by default
      });
      // Initialize controllers for the new contact
      _initializeControllers(newIndex);
    });
  }

  void _removeContact(int index) {
    setState(() {
      // Dispose controllers for this contact
      if (_controllers.containsKey(index)) {
        _controllers[index]!.values.forEach((controller) => controller.dispose());
        _controllers.remove(index);
      }
      
      _contacts.removeAt(index);
      
      // Rebuild controller map for remaining contacts
      final oldControllers = Map<int, Map<String, TextEditingController>>.from(_controllers);
      _controllers.clear();
      for (int i = 0; i < _contacts.length; i++) {
        if (oldControllers.containsKey(i + 1)) {
          _controllers[i] = oldControllers[i + 1]!;
        } else {
          _initializeControllers(i);
        }
      }
      
      // If we removed the primary contact, make the first one primary
      if (_contacts.isNotEmpty && !_contacts.any((c) => c['isPrimary'] == true)) {
        _contacts[0]['isPrimary'] = true;
      }
    });
  }

  void _setPrimary(int index) {
    setState(() {
      // Unset all primary flags
      for (var contact in _contacts) {
        contact['isPrimary'] = false;
      }
      // Set selected as primary
      _contacts[index]['isPrimary'] = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addContact,
            tooltip: 'Add Contact',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: AppColors.error),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loadContacts,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.info.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: AppColors.info),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Add emergency contacts who can be reached in case of an emergency.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.info,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(),

                      const SizedBox(height: 24),

                      // Contacts List
                      if (_contacts.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.contact_emergency,
                                  size: 64,
                                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No emergency contacts',
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap the + button to add a contact',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...List.generate(
                          _contacts.length,
                          (index) => _buildContactCard(index),
                        ),

                      const SizedBox(height: 24),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveContacts,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Save Contacts',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ).animate().fadeIn(delay: 200.ms),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildContactCard(int index) {
    final contact = _contacts[index];
    final isPrimary = contact['isPrimary'] == true;
    
    // Ensure controllers are initialized
    _initializeControllers(index);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrimary
              ? AppColors.primary.withValues(alpha: 0.5)
              : AppColors.cardBorder,
          width: isPrimary ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isPrimary)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'PRIMARY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              const Spacer(),
              if (!isPrimary)
                TextButton(
                  onPressed: () => _setPrimary(index),
                  child: const Text('Set as Primary'),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () => _removeContact(index),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('name_$index'),
            decoration: InputDecoration(
              labelText: 'Name *',
              prefixIcon: const Icon(Icons.person_outline),
              border: const OutlineInputBorder(),
            ),
            controller: _controllers[index]!['name'],
            onChanged: (value) {
              setState(() {
                contact['name'] = value;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('phone_$index'),
            decoration: InputDecoration(
              labelText: 'Phone Number *',
              prefixIcon: const Icon(Icons.phone_outlined),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            controller: _controllers[index]!['phone'],
            onChanged: (value) {
              setState(() {
                contact['phone'] = value;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('email_$index'),
            decoration: InputDecoration(
              labelText: 'Email (Optional)',
              prefixIcon: const Icon(Icons.email_outlined),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            controller: _controllers[index]!['email'],
            onChanged: (value) {
              setState(() {
                contact['email'] = value;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('relationship_$index'),
            decoration: InputDecoration(
              labelText: 'Relationship (Optional)',
              prefixIcon: const Icon(Icons.people_outline),
              border: const OutlineInputBorder(),
              hintText: 'e.g., Spouse, Parent, Friend',
            ),
            controller: _controllers[index]!['relationship'],
            onChanged: (value) {
              setState(() {
                contact['relationship'] = value;
              });
            },
          ),
        ],
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 100));
  }
}



