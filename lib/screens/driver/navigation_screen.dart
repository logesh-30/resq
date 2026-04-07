import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

class DriverNavigationScreen extends StatefulWidget {
  final String emergencyId;
  const DriverNavigationScreen({super.key, required this.emergencyId});

  @override
  State<DriverNavigationScreen> createState() => _DriverNavigationScreenState();
}

class _DriverNavigationScreenState extends State<DriverNavigationScreen> {
  bool _patientPickedUp = false;
  Timer? _locationTimer;
  LatLng? _driverLocation;
  LatLng? _patientLocation;
  List<Map<String, dynamic>> _nearbyHospitals = [];
  bool _loadingHospitals = false;

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
    _loadPatientLocation();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPatientLocation() async {
    final doc = await FirebaseFirestore.instance
        .collection('emergencies')
        .doc(widget.emergencyId)
        .get();
    final data = doc.data();
    if (data != null && data['userLocation'] != null) {
      final loc = data['userLocation'] as GeoPoint;
      setState(() => _patientLocation = LatLng(loc.latitude, loc.longitude));
    }
  }

  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        final latLng = LatLng(position.latitude, position.longitude);
        setState(() => _driverLocation = latLng);
        await FirebaseFirestore.instance
            .collection('emergencies')
            .doc(widget.emergencyId)
            .update({
          'driverLocation': GeoPoint(position.latitude, position.longitude),
          'eta': _calculateEta(position),
        });
      } catch (e) {
        debugPrint('Location error: $e');
      }
    });
  }

  int _calculateEta(Position position) {
    if (_patientLocation == null) return 10;
    const Distance distance = Distance();
    final meters = distance(
      LatLng(position.latitude, position.longitude),
      _patientLocation!,
    );
    return ((meters / 1000) * 3).ceil().clamp(1, 60);
  }

  Future<void> _loadNearbyHospitals() async {
    setState(() => _loadingHospitals = true);
    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final lat = position.latitude;
      final lon = position.longitude;
      final query = '''
[out:json][timeout:25];
(
  node["amenity"="hospital"](around:5000,$lat,$lon);
  way["amenity"="hospital"](around:5000,$lat,$lon);
  node["amenity"="clinic"](around:5000,$lat,$lon);
);
out body;
>;
out skel qt;
''';
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;
        final hospitals = <Map<String, dynamic>>[];
        for (final element in elements) {
          final tags = element['tags'] as Map<String, dynamic>?;
          if (tags != null) {
            final name = tags['name'] ?? tags['name:en'] ?? 'Unknown Hospital';
            final elLat = element['lat']?.toDouble();
            final elLon = element['lon']?.toDouble();
            if (elLat != null && elLon != null && name != 'Unknown Hospital') {
              const Distance distance = Distance();
              final meters = distance(
                LatLng(lat, lon),
                LatLng(elLat, elLon),
              );
              hospitals.add({
                'name': name,
                'lat': elLat,
                'lon': elLon,
                'distance': (meters / 1000).toStringAsFixed(1),
              });
            }
          }
        }
        hospitals.sort((a, b) =>
            double.parse(a['distance']).compareTo(double.parse(b['distance'])));
        setState(() {
          _nearbyHospitals = hospitals.take(6).toList();
          _loadingHospitals = false;
        });
      }
    } catch (e) {
      debugPrint('Hospital fetch error: $e');
      setState(() => _loadingHospitals = false);
    }
  }

  Future<void> _markPickedUp() async {
    await FirebaseFirestore.instance
        .collection('emergencies')
        .doc(widget.emergencyId)
        .update({'status': 'pickedUp'});
    setState(() => _patientPickedUp = true);
    await _loadNearbyHospitals();
  }

  Future<void> _completeEmergency() async {
    _locationTimer?.cancel();
    await FirebaseFirestore.instance
        .collection('emergencies')
        .doc(widget.emergencyId)
        .update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) context.go('/driver-dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        title: const Text('Active Emergency'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('emergencies')
            .doc(widget.emergencyId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) {
            return const Center(child: Text('Emergency not found'));
          }
          final medical = data['medicalProfile'] as Map<String, dynamic>? ?? {};
          final userLoc = data['userLocation'] as GeoPoint?;
          final driverLoc = data['driverLocation'] as GeoPoint?;
          final patientLatLng = userLoc != null
              ? LatLng(userLoc.latitude, userLoc.longitude)
              : const LatLng(13.0827, 80.2707);
          final driverLatLng = driverLoc != null
              ? LatLng(driverLoc.latitude, driverLoc.longitude)
              : _driverLocation;

          return Column(
            children: [
              SizedBox(
                height: 260,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: patientLatLng,
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
                          point: patientLatLng,
                          width: 60,
                          height: 60,
                          child: const Column(
                            children: [
                              Icon(Icons.person_pin_circle,
                                  color: Colors.blue, size: 40),
                              Text('Patient',
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
                                Text('You',
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
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Patient Information',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFD32F2F))),
                              const SizedBox(height: 12),
                              _infoRow('Name', data['userName'] ?? '-'),
                              _infoRow(
                                  'Emergency', data['emergencyType'] ?? '-'),
                              _infoRow(
                                  'Blood Group', medical['bloodGroup'] ?? '-'),
                              _infoRow(
                                  'Allergies', medical['allergies'] ?? '-'),
                              _infoRow(
                                  'Conditions', medical['conditions'] ?? '-'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_patientPickedUp)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _markPickedUp,
                            icon: const Icon(Icons.person_add),
                            label: const Text('Patient Picked Up'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      if (_patientPickedUp) ...[
                        const Text('Nearby Hospitals',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (_loadingHospitals)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  CircularProgressIndicator(
                                      color: Color(0xFFD32F2F)),
                                  SizedBox(height: 8),
                                  Text('Finding nearby hospitals...',
                                      style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          )
                        else if (_nearbyHospitals.isEmpty)
                          const Text('No hospitals found nearby',
                              style: TextStyle(color: Colors.grey))
                        else
                          ..._nearbyHospitals.map((hospital) => Card(
                                child: ListTile(
                                  leading: const Icon(Icons.local_hospital,
                                      color: Color(0xFFD32F2F)),
                                  title: Text(hospital['name']),
                                  subtitle:
                                      Text('${hospital['distance']} km away'),
                                  trailing: const Icon(Icons.arrow_forward_ios,
                                      size: 16),
                                  onTap: () async {
                                    await FirebaseFirestore.instance
                                        .collection('emergencies')
                                        .doc(widget.emergencyId)
                                        .update({'hospital': hospital['name']});
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(
                                            'Hospital set to ${hospital['name']}'),
                                      ));
                                    }
                                  },
                                ),
                              )),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _completeEmergency,
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Mark as Completed'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 100,
              child: Text('$label:',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
