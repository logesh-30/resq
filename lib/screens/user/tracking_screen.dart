import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';

class TrackingScreen extends StatelessWidget {
  final String emergencyId;
  const TrackingScreen({super.key, required this.emergencyId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        title: const Text('Ambulance Tracking'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('emergencies')
            .doc(emergencyId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) {
            return const Center(child: Text('Emergency not found'));
          }
          final status = data['status'] ?? 'pending';

          if (status == 'completed') {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 80),
                  const SizedBox(height: 16),
                  const Text('You have arrived safely',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => context.go('/dashboard'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white),
                    child: const Text('Back to Home'),
                  )
                ],
              ),
            );
          }

          if (status == 'pending') {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFFD32F2F)),
                  const SizedBox(height: 24),
                  const Text('Searching for nearby ambulance...',
                      style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text('Please stay calm and wait',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 48),
                  OutlinedButton(
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('emergencies')
                          .doc(emergencyId)
                          .update({'status': 'cancelled'});
                      if (context.mounted) context.go('/dashboard');
                    },
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red)),
                    child: const Text('Cancel Request'),
                  ),
                ],
              ),
            );
          }

          // Accepted or pickedUp — show live map
          final userLoc = data['userLocation'] as GeoPoint?;
          final driverLoc = data['driverLocation'] as GeoPoint?;

          final userLatLng = userLoc != null
              ? LatLng(userLoc.latitude, userLoc.longitude)
              : const LatLng(13.0827, 80.2707);

          final driverLatLng = driverLoc != null
              ? LatLng(driverLoc.latitude, driverLoc.longitude)
              : null;

          final center = driverLatLng ?? userLatLng;

          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.emergency.ambulance_app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: userLatLng,
                          width: 60,
                          height: 60,
                          child: const Column(
                            children: [
                              Icon(Icons.person_pin_circle,
                                  color: Colors.blue, size: 40),
                              Text('You',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue)),
                            ],
                          ),
                        ),
                        if (driverLatLng != null)
                          Marker(
                            point: driverLatLng,
                            width: 60,
                            height: 60,
                            child: const Column(
                              children: [
                                Icon(Icons.local_shipping,
                                    color: Color(0xFFD32F2F), size: 40),
                                Text('Ambulance',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFD32F2F))),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1), blurRadius: 10)
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFFD32F2F),
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['driverName'] ?? 'Driver assigned',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                'Ambulance: ${data['ambulanceId'] ?? '-'}',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer,
                                  color: Color(0xFFD32F2F), size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${data['eta'] ?? '...'} min',
                                style: const TextStyle(
                                    color: Color(0xFFD32F2F),
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (status == 'pickedUp') ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.local_hospital,
                                color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Going to: ${data['hospital'] ?? 'Selecting hospital...'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
