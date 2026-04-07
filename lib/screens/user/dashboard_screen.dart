import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _checkActiveEmergency();
  }

  Future<void> _checkActiveEmergency() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final query = await FirebaseFirestore.instance
        .collection('emergencies')
        .where('userId', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'accepted', 'pickedUp'])
        .limit(1)
        .get();
    if (query.docs.isNotEmpty && mounted) {
      context.go('/tracking/${query.docs.first.id}');
    }
  }

  int _getWaitSeconds(String emergencyType) {
    switch (emergencyType) {
      case 'Heart Problem':
      case 'Road Accident':
        return 60;
      case 'Pregnancy Emergency':
        return 90;
      case 'General Emergency':
      default:
        return 120;
    }
  }

  Future<String?> _showEmergencyTypeDialog() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Emergency Type',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('What is the emergency?',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ...[
                ('Road Accident', Icons.car_crash, Colors.red),
                ('Heart Problem', Icons.favorite, Colors.red),
                ('Pregnancy Emergency', Icons.pregnant_woman, Colors.orange),
                ('General Emergency', Icons.emergency, Colors.blue),
              ].map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, item.$1),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: item.$3.withOpacity(0.4)),
                          borderRadius: BorderRadius.circular(8),
                          color: item.$3.withOpacity(0.05),
                        ),
                        child: Row(
                          children: [
                            Icon(item.$2, color: item.$3),
                            const SizedBox(width: 12),
                            Text(item.$1, style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'General Emergency'),
              child: const Text('Skip', style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _triggerEmergency() async {
    final emergencyType = await _showEmergencyTypeDialog();
    if (emergencyType == null) return;
    setState(() {
      _loading = true;
      _statusMessage = 'Getting your location...';
    });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() => _statusMessage = 'Sending emergency request...');
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data()!;
      final emergencyId = const Uuid().v4();
      final waitSeconds = _getWaitSeconds(emergencyType);
      await FirebaseFirestore.instance
          .collection('emergencies')
          .doc(emergencyId)
          .set({
        'id': emergencyId,
        'userId': uid,
        'userName': userData['name'],
        'userLocation': GeoPoint(position.latitude, position.longitude),
        'emergencyType': emergencyType,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'medicalProfile': userData['medicalProfile'] ?? {},
        'emergencyContact': userData['emergencyContact'] ?? {},
        'dispatchTier': 1,
        'tierWaitSeconds': waitSeconds,
        'tierStartedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      context.go('/tracking/$emergencyId');
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Emergency',
            style: TextStyle(
                color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.grey),
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Press for Emergency Help',
                style: TextStyle(fontSize: 20, color: Colors.grey)),
            const SizedBox(height: 48),
            GestureDetector(
              onTap: _loading ? null : _triggerEmergency,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _loading ? 180 : 220,
                height: _loading ? 180 : 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      _loading ? Colors.red.shade300 : const Color(0xFFD32F2F),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 10,
                    )
                  ],
                ),
                child: _loading
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              _statusMessage ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ],
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.emergency, color: Colors.white, size: 64),
                          SizedBox(height: 8),
                          Text('SOS',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 48),
            const Text('Tap the button to call an ambulance',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
