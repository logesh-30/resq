import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  bool _isOnline = false;
  bool _loading = false;
  Position? _driverPosition;
  final Set<String> _notifiedEmergencies = {};

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadOnlineStatus();
    _checkActiveRequest();
    _saveFCMToken();
    _listenToForegroundMessages();
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await flutterLocalNotificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {},
    );
  }

  Future<void> _showLocalNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Alerts',
      channelDescription: 'Notifications for emergency requests',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  Future<void> _saveFCMToken() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmToken': token});
    }
  }

  void _listenToForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (!mounted) return;
      final notification = message.notification;
      if (notification != null) {
        _showLocalNotification(
          notification.title ?? 'Emergency Alert',
          notification.body ?? 'A patient needs help nearby',
        );
      }
    });
  }

  Future<void> _loadOnlineStatus() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (mounted) {
      setState(() => _isOnline = doc.data()?['isOnline'] ?? false);
    }
  }

  Future<void> _checkActiveRequest() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final query = await FirebaseFirestore.instance
        .collection('emergencies')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['accepted', 'pickedUp'])
        .limit(1)
        .get();
    if (query.docs.isNotEmpty && mounted) {
      context.go('/driver-navigation/${query.docs.first.id}');
    }
  }

  double _getDistanceKm(Map<String, dynamic> data) {
    if (_driverPosition == null) return 999;
    final userLoc = data['userLocation'] as GeoPoint?;
    if (userLoc == null) return 999;
    const Distance distance = Distance();
    final meters = distance(
      LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
      LatLng(userLoc.latitude, userLoc.longitude),
    );
    return meters / 1000;
  }

  // Check if this driver should see this emergency based on tier and time
  bool _shouldShowEmergency(Map<String, dynamic> data) {
    if (_driverPosition == null) return true;
    final distanceKm = _getDistanceKm(data);
    final tier = data['dispatchTier'] ?? 1;
    final tierStartedAt = data['tierStartedAt'];
    final tierWaitSeconds = data['tierWaitSeconds'] ?? 120;

    // Calculate seconds elapsed since tier started
    int secondsElapsed = 0;
    if (tierStartedAt != null) {
      final startTime = tierStartedAt.toDate() as DateTime;
      secondsElapsed = DateTime.now().difference(startTime).inSeconds;
    }

    // Tier 1: Only show to drivers within 3km
    if (distanceKm <= 3) return true;

    // Tier 2: Show to drivers within 6km after wait time
    if (distanceKm <= 6 && secondsElapsed >= tierWaitSeconds) return true;

    // Tier 3: Show to all drivers after double wait time
    if (secondsElapsed >= tierWaitSeconds * 2) return true;

    return false;
  }

  int _getSeverityScore(String emergencyType) {
    switch (emergencyType) {
      case 'Heart Problem':
      case 'Road Accident':
        return 100;
      case 'Pregnancy Emergency':
        return 70;
      case 'General Emergency':
      default:
        return 40;
    }
  }

  Color _getSeverityColor(String emergencyType) {
    switch (emergencyType) {
      case 'Heart Problem':
      case 'Road Accident':
        return Colors.red;
      case 'Pregnancy Emergency':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  IconData _getSeverityIcon(String emergencyType) {
    switch (emergencyType) {
      case 'Heart Problem':
        return Icons.favorite;
      case 'Pregnancy Emergency':
        return Icons.pregnant_woman;
      case 'Road Accident':
        return Icons.car_crash;
      default:
        return Icons.emergency;
    }
  }

  double _getDistanceScore(double distanceKm) {
    if (distanceKm < 1) return 100;
    if (distanceKm < 2) return 80;
    if (distanceKm < 5) return 60;
    if (distanceKm < 10) return 40;
    return 20;
  }

  double _getTotalScore(Map<String, dynamic> data) {
    final severityScore =
        _getSeverityScore(data['emergencyType'] ?? 'General Emergency');
    final distanceKm = _getDistanceKm(data);
    final distanceScore = _getDistanceScore(distanceKm);
    return (severityScore * 0.6) + (distanceScore * 0.4);
  }

  String _getDistanceText(Map<String, dynamic> data) {
    if (_driverPosition == null) return 'Distance unknown';
    final km = _getDistanceKm(data);
    if (km == 999) return 'Distance unknown';
    return '${km.toStringAsFixed(1)} km away';
  }

  String _getDispatchStatus(Map<String, dynamic> data) {
    if (_driverPosition == null) return '';
    final distanceKm = _getDistanceKm(data);
    final tierWaitSeconds = data['tierWaitSeconds'] ?? 120;
    final tierStartedAt = data['tierStartedAt'];
    int secondsElapsed = 0;
    if (tierStartedAt != null) {
      final startTime = tierStartedAt.toDate() as DateTime;
      secondsElapsed = DateTime.now().difference(startTime).inSeconds;
    }
    if (distanceKm <= 3) return 'Priority dispatch — you are nearest';
    if (distanceKm <= 6 && secondsElapsed >= tierWaitSeconds) {
      return 'Expanded dispatch — nearest driver did not respond';
    }
    return 'Broadcast dispatch — urgent help needed';
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      if (value) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        setState(() => _driverPosition = position);
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'isOnline': true,
          'currentLocation': GeoPoint(position.latitude, position.longitude),
        });
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'isOnline': false});
        setState(() => _driverPosition = null);
      }
      setState(() => _isOnline = value);
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go('/');
  }

  Future<void> _acceptEmergency(
      String emergencyId, Map<String, dynamic> data, String uid) async {
    final driverDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final driverData = driverDoc.data()!;
    await FirebaseFirestore.instance
        .collection('emergencies')
        .doc(emergencyId)
        .update({
      'status': 'accepted',
      'driverId': uid,
      'driverName': driverData['name'],
      'ambulanceId': driverData['ambulanceId'] ?? '',
      'eta': 10,
    });
    if (mounted) {
      context.go('/driver-navigation/$emergencyId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        title: const Text('Driver Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout)
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: _isOnline ? Colors.green.shade50 : Colors.grey.shade100,
            child: Column(
              children: [
                Icon(
                  _isOnline ? Icons.wifi : Icons.wifi_off,
                  size: 48,
                  color: _isOnline ? Colors.green : Colors.grey,
                ),
                const SizedBox(height: 8),
                Text(
                  _isOnline ? 'You are Online' : 'You are Offline',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _isOnline ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isOnline
                      ? 'You will receive emergency alerts'
                      : 'Go online to receive emergencies',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                _loading
                    ? const CircularProgressIndicator()
                    : Switch(
                        value: _isOnline,
                        onChanged: _toggleOnline,
                        activeColor: Colors.green,
                      ),
              ],
            ),
          ),
          if (_isOnline) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.sort, color: Colors.grey, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Smart dispatch — sorted by severity + distance',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('emergencies')
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Filter by dispatch tier
                  final visibleDocs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _shouldShowEmergency(data);
                  }).toList();

                  // Show notifications for new emergencies
                  for (final doc in visibleDocs) {
                    if (!_notifiedEmergencies.contains(doc.id)) {
                      _notifiedEmergencies.add(doc.id);
                      final data = doc.data() as Map<String, dynamic>;
                      _showLocalNotification(
                        '🚨 Emergency Alert!',
                        '${data['userName']} needs help — ${data['emergencyType']}',
                      );
                    }
                  }

                  if (visibleDocs.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.hourglass_empty,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('No emergencies nearby',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  // Sort by smart score
                  visibleDocs.sort((a, b) {
                    final dataA = a.data() as Map<String, dynamic>;
                    final dataB = b.data() as Map<String, dynamic>;
                    return _getTotalScore(dataB)
                        .compareTo(_getTotalScore(dataA));
                  });

                  return ListView.builder(
                    itemCount: visibleDocs.length,
                    itemBuilder: (context, index) {
                      final data =
                          visibleDocs[index].data() as Map<String, dynamic>;
                      final emergencyId = visibleDocs[index].id;
                      final emergencyType =
                          data['emergencyType'] ?? 'General Emergency';
                      final severityColor = _getSeverityColor(emergencyType);
                      final severityIcon = _getSeverityIcon(emergencyType);
                      final distanceText = _getDistanceText(data);
                      final score = _getTotalScore(data).toInt();
                      final dispatchStatus = _getDispatchStatus(data);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: severityColor.withOpacity(0.3),
                              width: 1.5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor:
                                            severityColor.withOpacity(0.15),
                                        child: Icon(severityIcon,
                                            color: severityColor),
                                      ),
                                      const SizedBox(width: 10),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            data['userName'] ?? 'Unknown',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16),
                                          ),
                                          Text(
                                            emergencyType,
                                            style: TextStyle(
                                                color: severityColor,
                                                fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: severityColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Score: $score',
                                      style: TextStyle(
                                          color: severityColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(distanceText,
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 13)),
                                ],
                              ),
                              if (dispatchStatus.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.info_outline,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        dispatchStatus,
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () =>
                                      _acceptEmergency(emergencyId, data, uid),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: severityColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Accept Emergency'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
