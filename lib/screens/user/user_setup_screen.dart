import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

class UserSetupScreen extends StatefulWidget {
  const UserSetupScreen({super.key});

  @override
  State<UserSetupScreen> createState() => _UserSetupScreenState();
}

class _UserSetupScreenState extends State<UserSetupScreen> {
  final _ageController = TextEditingController();
  final _bloodGroupController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactRelationController = TextEditingController();
  bool _loading = false;
  String? _error;

  final List<String> _bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'O+',
    'O-',
    'AB+',
    'AB-'
  ];
  String _selectedBloodGroup = 'O+';

  Future<void> _saveProfile() async {
    if (_ageController.text.isEmpty ||
        _contactNameController.text.isEmpty ||
        _contactPhoneController.text.isEmpty ||
        _contactRelationController.text.isEmpty) {
      setState(() => _error = 'Please fill all required fields');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'medicalProfile': {
          'age': int.tryParse(_ageController.text) ?? 0,
          'bloodGroup': _selectedBloodGroup,
          'allergies': _allergiesController.text.trim(),
          'conditions': _conditionsController.text.trim(),
          'medications': _medicationsController.text.trim(),
        },
        'emergencyContact': {
          'name': _contactNameController.text.trim(),
          'phone': _contactPhoneController.text.trim(),
          'relation': _contactRelationController.text.trim(),
        },
        'profileComplete': true,
      });
      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Medical Profile'),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Medical Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text('This helps ambulance staff prepare for your care',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            TextField(
              controller: _ageController,
              decoration: const InputDecoration(
                labelText: 'Age *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedBloodGroup,
              decoration: const InputDecoration(
                labelText: 'Blood Group *',
                border: OutlineInputBorder(),
              ),
              items: _bloodGroups
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedBloodGroup = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _allergiesController,
              decoration: const InputDecoration(
                labelText: 'Known Allergies',
                border: OutlineInputBorder(),
                hintText: 'e.g. Penicillin, Peanuts',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _conditionsController,
              decoration: const InputDecoration(
                labelText: 'Major Medical Conditions',
                border: OutlineInputBorder(),
                hintText: 'e.g. Diabetes, Hypertension',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _medicationsController,
              decoration: const InputDecoration(
                labelText: 'Current Medications (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            const Text('Emergency Contact',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text('They will be notified when you trigger an emergency',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            TextField(
              controller: _contactNameController,
              decoration: const InputDecoration(
                labelText: 'Contact Name *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contactPhoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contactRelationController,
              decoration: const InputDecoration(
                labelText: 'Relationship *',
                border: OutlineInputBorder(),
                hintText: 'e.g. Mother, Brother',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save & Continue',
                        style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
