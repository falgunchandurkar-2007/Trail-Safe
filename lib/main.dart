import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Telephony telephony = Telephony.instance;
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// Background SMS Listener for incoming mesh packets
@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  final body = message.body ?? "";
  final sender = message.address ?? "Unknown";

  if (body.startsWith("[TS_MESH]")) {
    final prefs = await SharedPreferences.getInstance();
    final myPhone = prefs.getString('user_phone') ?? "";

    // DROP duplicate loopback if message originated from current device
    if (sender.isNotEmpty && myPhone.isNotEmpty && sender.contains(myPhone.replaceAll("+", ""))) {
      return;
    }

    List<String> rawMsgs = prefs.getStringList('mesh_chat_history') ?? [];
    final cleanText = body.replaceFirst("[TS_MESH]", "").trim();
    
    // Check if it's a join notification broadcast
    if (cleanText.startsWith("EVENT_JOIN:")) {
      final joinedName = cleanText.replaceFirst("EVENT_JOIN:", "").trim();
      rawMsgs.add(jsonEncode({
        'sender': 'SYSTEM',
        'text': '⚡ $joinedName has entered the secure room.',
        'isMe': false,
        'isSystem': true,
        'timestamp': DateTime.now().toIso8601String()
      }));
      // Auto-save member to room contact list if new
      List<String> rawMems = prefs.getStringList('room_members') ?? [];
      bool exists = rawMems.any((m) => (jsonDecode(m)['phone'] as String) == sender);
      if (!exists) {
        rawMems.add(jsonEncode({'name': joinedName, 'phone': sender}));
        await prefs.setStringList('room_members', rawMems);
      }
    } else {
      rawMsgs.add(jsonEncode({
        'sender': sender,
        'text': cleanText,
        'isMe': false,
        'isSystem': false,
        'timestamp': DateTime.now().toIso8601String()
      }));
    }
    await prefs.setStringList('mesh_chat_history', rawMsgs);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrailSafeApp());
}

class TrailSafeApp extends StatelessWidget {
  const TrailSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'TrailSafe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09140E),
        primaryColor: const Color(0xFF00E676),
        fontFamily: 'monospace',
      ),
      home: const AuthGateScreen(),
    );
  }
}

// ---------------- AUTH CHECK / GATE ----------------
class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});
  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  void _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone');
    if (!mounted) return;
    if (phone != null && phone.isNotEmpty) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigationScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginRegistrationScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF09140E),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
    );
  }
}

// ---------------- LOGIN WITH NAME & OTP SCREEN ----------------
class LoginRegistrationScreen extends StatefulWidget {
  const LoginRegistrationScreen({super.key});
  @override
  State<LoginRegistrationScreen> createState() => _LoginRegistrationScreenState();
}

class _LoginRegistrationScreenState extends State<LoginRegistrationScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String? generatedOTP;
  bool isOtpSent = false;

  void _sendOTP() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter your full name")));
      return;
    }
    if (_phoneCtrl.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a valid 10-digit mobile number")));
      return;
    }

    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();

    final otp = (1000 + Random().nextInt(9000)).toString();
    setState(() {
      generatedOTP = otp;
      isOtpSent = true;
    });

    telephony.sendSms(
      to: _phoneCtrl.text.trim(),
      message: "[TrailSafe] Welcome ${_nameCtrl.text.trim()}! Your authentication OTP is: $otp",
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF132B1F),
        content: Text("⚡ OTP Sent to ${_phoneCtrl.text}: $otp", style: const TextStyle(color: Color(0xFF00E676))),
      ),
    );
  }

  void _verifyAndRegister() async {
    if (_otpCtrl.text.trim() == generatedOTP) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.heavyImpact();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', _nameCtrl.text.trim());
      await prefs.setString('user_phone', _phoneCtrl.text.trim());
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigationScreen()));
      }
    } else {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid OTP code. Please retry.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00E676), width: 2),
                    boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.2), blurRadius: 20)],
                  ),
                  child: const Icon(Icons.shield_outlined, size: 50, color: Color(0xFF00E676)),
                ),
                const SizedBox(height: 18),
                const Text("TRAILSAFE TERMINAL", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white)),
                const Text("IDENTITY VERIFICATION GATEWAY", style: TextStyle(fontSize: 10, color: Color(0xFF00E676), letterSpacing: 1.5)),
                const SizedBox(height: 30),

                // Name Input Field
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF00E676)),
                    hintText: "Full Name (Trekker Identity)",
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: const Color(0xFF132B1F),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),

                // Phone Input Field
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.phone_android, color: Color(0xFF00E676)),
                    hintText: "Mobile Number (+91...)",
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: const Color(0xFF132B1F),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),

                if (isOtpSent) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 18),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: "4-DIGIT OTP",
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), letterSpacing: 1),
                      filled: true,
                      fillColor: const Color(0xFF132B1F),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ],

                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isOtpSent ? _verifyAndRegister : _sendOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isOtpSent ? "VERIFY & INITIALIZE" : "SEND SMS OTP CODE",
                      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- MAIN NAVIGATION SCREEN ----------------
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const SOSHomeScreen(),
    const RoomHubScreen(),
    const MeshGroupChatScreen(),
    const HospitalRadarScreen(),
    const UserProfileDetailsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          SystemSound.play(SystemSoundType.click);
          setState(() => _currentIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF060E0A),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: const Color(0xFF4A6B59),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.error_outline), label: 'SOS'),
          BottomNavigationBarItem(icon: Icon(Icons.meeting_room_outlined), label: 'Room'),
          BottomNavigationBarItem(icon: Icon(Icons.forum_outlined), label: 'Mesh Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.local_hospital_outlined), label: 'Hospitals'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

// ---------------- 1. SOS HOME SCREEN ----------------
class SOSHomeScreen extends StatefulWidget {
  const SOSHomeScreen({super.key});
  @override
  State<SOSHomeScreen> createState() => _SOSHomeScreenState();
}

class _SOSHomeScreenState extends State<SOSHomeScreen> {
  String _selectedEmergency = "Injury";
  String _gpsText = "Tap refresh to get GPS coordinates";
  bool _fetchingGps = false;
  Position? _currentPosition;
  String _activeRoomCode = "NO ACTIVE ROOM";

  final List<Map<String, dynamic>> emergencies = [
    {"label": "Injury", "icon": Icons.healing},
    {"label": "Snake Bite", "icon": Icons.pest_control_rounded},
    {"label": "Lost", "icon": Icons.help_outline},
    {"label": "Bad Weather", "icon": Icons.thunderstorm_outlined},
    {"label": "Medical", "icon": Icons.medical_services_outlined},
    {"label": "General SOS", "icon": Icons.warning_amber_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _initSMSListener();
    _getGPS();
    _loadRoomStatus();
  }

  void _loadRoomStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _activeRoomCode = prefs.getString('current_room_code') ?? "NO ACTIVE ROOM";
    });
  }

  void _initSMSListener() async {
    await telephony.requestPhoneAndSmsPermissions;
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage msg) async {
        final body = msg.body ?? "";
        final sender = msg.address ?? "Unknown";
        final prefs = await SharedPreferences.getInstance();
        final myPhone = prefs.getString('user_phone') ?? "";

        // Drop incoming self-sent loopbacks
        if (sender.isNotEmpty && myPhone.isNotEmpty && sender.contains(myPhone.replaceAll("+", ""))) {
          return;
        }

        if (body.startsWith("[TS_MESH]")) {
          final cleanText = body.replaceFirst("[TS_MESH]", "").trim();
          List<String> rawMsgs = prefs.getStringList('mesh_chat_history') ?? [];

          if (cleanText.startsWith("EVENT_JOIN:")) {
            final joinedName = cleanText.replaceFirst("EVENT_JOIN:", "").trim();
            rawMsgs.add(jsonEncode({
              'sender': 'SYSTEM',
              'text': '⚡ $joinedName has entered the room.',
              'isMe': false,
              'isSystem': true,
              'timestamp': DateTime.now().toIso8601String()
            }));
            
            List<String> rawMems = prefs.getStringList('room_members') ?? [];
            bool exists = rawMems.any((m) => (jsonDecode(m)['phone'] as String) == sender);
            if (!exists) {
              rawMems.add(jsonEncode({'name': joinedName, 'phone': sender}));
              await prefs.setStringList('room_members', rawMems);
            }
          } else {
            rawMsgs.add(jsonEncode({
              'sender': sender,
              'text': cleanText,
              'isMe': false,
              'isSystem': false,
              'timestamp': DateTime.now().toIso8601String()
            }));
          }

          await prefs.setStringList('mesh_chat_history', rawMsgs);

          // If payload is an Emergency SOS Alert, show high priority popup
          if (cleanText.contains("SOS ALERT")) {
            SystemSound.play(SystemSoundType.alert);
            HapticFeedback.heavyImpact();
            _showEmergencyPopup(sender, cleanText);
          } else {
            SystemSound.play(SystemSoundType.alert);
            HapticFeedback.vibrate();

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF132B1F),
                  content: Text("🚨 Signal from $sender: $cleanText", style: const TextStyle(color: Color(0xFF00E676))),
                ),
              );
            }
          }
        }
      },
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );
  }

  void _showEmergencyPopup(String senderPhone, String alertText) {
    final ctx = appNavigatorKey.currentContext ?? context;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.warning_rounded, color: Color(0xFFDC2626), size: 30),
                    SizedBox(width: 10),
                    Text(
                      "Emergency alert",
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'sans-serif',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  "Alert received from $senderPhone:\n\n$alertText\n\nImmediate assistance required.",
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    height: 1.4,
                    fontFamily: 'sans-serif',
                  ),
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text("ACKNOWLEDGE", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'sans-serif')),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _getGPS() async {
    setState(() => _fetchingGps = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = pos;
        _gpsText = "LAT: ${pos.latitude.toStringAsFixed(5)} | LON: ${pos.longitude.toStringAsFixed(5)}";
        _fetchingGps = false;
      });
    } catch (e) {
      setState(() {
        _gpsText = "Satellites Connected (Offline Mode)";
        _fetchingGps = false;
      });
    }
  }

  void _triggerEmergencySOS() async {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();

    final prefs = await SharedPreferences.getInstance();
    final myName = prefs.getString('user_name') ?? 'Trekker';
    List<String> members = prefs.getStringList('room_members') ?? [];

    String coords = _currentPosition != null 
      ? "https://maps.google.com/?q=${_currentPosition!.latitude},${_currentPosition!.longitude}"
      : "GPS Satellite Fix";

    String payload = "[TS_MESH] 🚨 SOS ALERT from $myName: $_selectedEmergency! Location: $coords";

    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No room members found! Host or Join a room in Room tab.")),
      );
      return;
    }

    final myPhone = prefs.getString('user_phone') ?? '';

    // Broadcast SMS to all peer nodes EXCEPT current device
    for (var m in members) {
      final decoded = jsonDecode(m);
      if (decoded['phone'] != myPhone) {
        telephony.sendSms(to: decoded['phone'], message: payload);
      }
    }

    List<String> rawMsgs = prefs.getStringList('mesh_chat_history') ?? [];
    rawMsgs.add(jsonEncode({
      'sender': 'ME (SOS)',
      'text': "🚨 EMERGENCY DISPATCH: $_selectedEmergency ($coords)",
      'isMe': true,
      'isSystem': false,
      'timestamp': DateTime.now().toIso8601String()
    }));
    await prefs.setStringList('mesh_chat_history', rawMsgs);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text("⚡ SOS DISPATCHED TO REGISTERED MEMBERS", style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("TrailSafe", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF132B1F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00E676)),
                  ),
                  child: Text("ROOM: $_activeRoomCode", style: const TextStyle(fontSize: 10, color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // GPS Status Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF10241A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1F4330)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFF00E676), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("GPS LOCATION", style: TextStyle(fontSize: 10, color: Color(0xFF4ADE80), letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(_gpsText, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: _fetchingGps 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E676)))
                      : const Icon(Icons.refresh, color: Color(0xFF4ADE80)),
                    onPressed: _getGPS,
                  )
                ],
              ),
            ),

            const Spacer(),

            // Red Circular SOS
            Center(
              child: GestureDetector(
                onTap: _triggerEmergencySOS,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF7F1D1D), width: 3),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.35), blurRadius: 35, spreadRadius: 4),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 165,
                      height: 165,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFEF4444),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("SOS", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
                          Text("Press to alert", style: TextStyle(fontSize: 11, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const Spacer(),

            const Text("SELECT EMERGENCY TYPE", style: TextStyle(fontSize: 11, color: Color(0xFF4ADE80), letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: emergencies.map((item) {
                final isSelected = _selectedEmergency == item['label'];
                return GestureDetector(
                  onTap: () {
                    SystemSound.play(SystemSoundType.click);
                    setState(() => _selectedEmergency = item['label']);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFDC2626) : const Color(0xFF132B1F),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? const Color(0xFFEF4444) : const Color(0xFF1F4330)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(item['icon'], size: 16, color: isSelected ? Colors.white : const Color(0xFF4ADE80)),
                        const SizedBox(width: 6),
                        Text(item['label'], style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.white70)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF10241A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1F4330)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.group, color: Color(0xFF4ADE80), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text("Offline mesh linked. Manage room nodes in Room tab.", style: TextStyle(fontSize: 11, color: Colors.white70)),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- 2. HOST / JOIN ROOM HUB SCREEN ----------------
class RoomHubScreen extends StatefulWidget {
  const RoomHubScreen({super.key});
  @override
  State<RoomHubScreen> createState() => _RoomHubScreenState();
}

class _RoomHubScreenState extends State<RoomHubScreen> {
  final _roomCodeCtrl = TextEditingController();
  final _hostPhoneCtrl = TextEditingController();
  String _currentRoom = "None";
  List<Map<String, dynamic>> _roomMembers = [];

  @override
  void initState() {
    super.initState();
    _loadRoomData();
  }

  void _loadRoomData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawMems = prefs.getStringList('room_members') ?? [];
    setState(() {
      _currentRoom = prefs.getString('current_room_code') ?? "None";
      _roomMembers = rawMems.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    });
  }

  void _hostNewRoom() async {
    final code = "TRK-${1000 + Random().nextInt(9000)}";
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_room_code', code);
    
    // Add Host to room members
    final myName = prefs.getString('user_name') ?? 'Host';
    final myPhone = prefs.getString('user_phone') ?? '';
    List<String> mems = [jsonEncode({'name': myName, 'phone': myPhone, 'role': 'HOST'})];
    await prefs.setStringList('room_members', mems);

    _loadRoomData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: const Color(0xFF132B1F), content: Text("⚡ Hosted Room: $code", style: const TextStyle(color: Color(0xFF00E676)))),
    );
  }

  void _joinRoomByHostPhone() async {
    final hostPhone = _hostPhoneCtrl.text.trim();
    final roomCode = _roomCodeCtrl.text.trim();
    if (hostPhone.length < 10 || roomCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter valid Room Code and Host Mobile Number")));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final myName = prefs.getString('user_name') ?? 'Trekker';
    await prefs.setString('current_room_code', roomCode);

    // Save Host to local room members
    List<String> rawMems = prefs.getStringList('room_members') ?? [];
    rawMems.add(jsonEncode({'name': 'Host / Peer', 'phone': hostPhone}));
    await prefs.setStringList('room_members', rawMems);

    // Broadcast Join Notification to the Host via SMS
    telephony.sendSms(
      to: hostPhone,
      message: "[TS_MESH] EVENT_JOIN: $myName",
    );

    // Log in local chat
    List<String> rawMsgs = prefs.getStringList('mesh_chat_history') ?? [];
    rawMsgs.add(jsonEncode({
      'sender': 'SYSTEM',
      'text': '⚡ You joined Room $roomCode. Sent join broadcast to $hostPhone.',
      'isMe': true,
      'isSystem': true,
      'timestamp': DateTime.now().toIso8601String()
    }));
    await prefs.setStringList('mesh_chat_history', rawMsgs);

    _loadRoomData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: const Color(0xFF132B1F), content: Text("Joined Room $roomCode! Notification broadcasted to $hostPhone.", style: const TextStyle(color: Color(0xFF00E676)))),
    );
  }

  void _addManualMember() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF10241A),
        title: const Text("ADD ROOM MEMBER (NODE)", style: TextStyle(color: Color(0xFF00E676), fontSize: 13)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Member Name")),
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Phone (+91...)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
            onPressed: () async {
              if (phoneCtrl.text.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                List<String> mems = prefs.getStringList('room_members') ?? [];
                mems.add(jsonEncode({'name': nameCtrl.text.trim(), 'phone': phoneCtrl.text.trim()}));
                await prefs.setStringList('room_members', mems);
                _loadRoomData();
                Navigator.pop(context);
              }
            },
            child: const Text("ADD TO ROOM"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ROOM LOBBY & NODES", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),

            // Active Room Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF10241A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E676)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("ACTIVE MESH ROOM", style: TextStyle(fontSize: 10, color: Color(0xFF4ADE80), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(_currentRoom, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _hostNewRoom,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
                    child: const Text("HOST NEW ROOM", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Join Room Section
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF132B1F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1F4330)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("JOIN EXISTING ROOM", style: TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _roomCodeCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: "Enter Room Code (e.g. TRK-4821)", isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _hostPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: "Enter Host/Peer Phone (+91...)", isDense: true),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _joinRoomByHostPhone,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E4D34), foregroundColor: const Color(0xFF00E676)),
                      child: const Text("JOIN & BROADCAST NOTIFICATION"),
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("ROOM MEMBERS (${_roomMembers.length})", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80))),
                IconButton(icon: const Icon(Icons.person_add, color: Color(0xFF00E676)), onPressed: _addManualMember),
              ],
            ),

            Expanded(
              child: _roomMembers.isEmpty
                ? const Center(child: Text("No registered members yet. Host, join, or add nodes above.", style: TextStyle(color: Colors.white38, fontSize: 11)))
                : ListView.builder(
                    itemCount: _roomMembers.length,
                    itemBuilder: (_, i) {
                      final m = _roomMembers[i];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10241A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF1F4330)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                Text(m['phone'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF4ADE80))),
                              ],
                            ),
                            const Icon(Icons.check_circle, color: Color(0xFF00E676), size: 18),
                          ],
                        ),
                      );
                    },
                  ),
            )
          ],
        ),
      ),
    );
  }
}

// ---------------- 3. OFFLINE MESH GROUP CHAT SCREEN ----------------
class MeshGroupChatScreen extends StatefulWidget {
  const MeshGroupChatScreen({super.key});
  @override
  State<MeshGroupChatScreen> createState() => _MeshGroupChatScreenState();
}

class _MeshGroupChatScreenState extends State<MeshGroupChatScreen> {
  final _msgCtrl = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _refreshChat();
    Timer.periodic(const Duration(seconds: 2), (_) => _refreshChat());
  }

  void _refreshChat() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawMsgs = prefs.getStringList('mesh_chat_history') ?? [];
    List<String> rawMems = prefs.getStringList('room_members') ?? [];

    if (mounted) {
      setState(() {
        _messages = rawMsgs.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
        _members = rawMems.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
      });
    }
  }

  void _sendGroupMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();

    final prefs = await SharedPreferences.getInstance();
    final myName = prefs.getString('user_name') ?? 'Me';

    // Save only to local database / state (DO NOT SEND EXTERNAL SMS FOR REGULAR CHAT)
    List<String> rawMsgs = prefs.getStringList('mesh_chat_history') ?? [];
    rawMsgs.add(jsonEncode({
      'sender': myName,
      'text': text,
      'isMe': true,
      'isSystem': false,
      'timestamp': DateTime.now().toIso8601String()
    }));
    await prefs.setStringList('mesh_chat_history', rawMsgs);

    _refreshChat();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF10241A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("SHARED OFFLINE MESH CHAT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    Text("ACTIVE MEMBERS: ${_members.length}", style: const TextStyle(fontSize: 10, color: Color(0xFF00E676))),
                  ],
                ),
                const Icon(Icons.wifi_tethering, color: Color(0xFF00E676), size: 20),
              ],
            ),
          ),

          Expanded(
            child: _messages.isEmpty
              ? const Center(child: Text("No messages yet. Send an offline text to all room members!", style: TextStyle(color: Colors.white38, fontSize: 11)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    final isMe = m['isMe'] == true;
                    final isSystem = m['isSystem'] == true;

                    if (isSystem) {
                      return Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF132B1F),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3)),
                          ),
                          child: Text(m['text'] ?? '', style: const TextStyle(fontSize: 10, color: Color(0xFF00E676))),
                        ),
                      );
                    }

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF1E4D34) : const Color(0xFF132B1F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isMe ? const Color(0xFF00E676) : const Color(0xFF2A5940)),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Text(m['sender'] ?? '', style: TextStyle(fontSize: 9, color: isMe ? const Color(0xFF4ADE80) : Colors.amber, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(m['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF060E0A),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Broadcast over offline mesh...",
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      filled: true,
                      fillColor: const Color(0xFF10241A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF00E676)),
                  onPressed: _sendGroupMessage,
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ---------------- 4. HOSPITALS RADAR SCREEN ----------------
class HospitalRadarScreen extends StatelessWidget {
  const HospitalRadarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> mockHospitals = [
      {"name": "District Emergency Trauma Centre", "dist": "3.4 km", "contact": "108"},
      {"name": "Wilderness Rescue First Post", "dist": "6.1 km", "contact": "112"},
      {"name": "Valley Base Medical Station", "dist": "11.8 km", "contact": "+91 9876543210"},
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("OFFLINE MEDICAL RADAR", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text("PRE-CACHED EMERGENCY DISPATCH POSTS", style: TextStyle(fontSize: 10, color: Color(0xFF00E676), letterSpacing: 1.2)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: mockHospitals.length,
                itemBuilder: (_, i) {
                  final h = mockHospitals[i];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10241A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1F4330)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h['name']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text("Triangulated Distance: ${h['dist']}", style: const TextStyle(fontSize: 11, color: Color(0xFF4ADE80))),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.call, color: Color(0xFF00E676)),
                          onPressed: () {
                            telephony.sendSms(to: h['contact']!, message: "[TS_MESH] REQUESTING MEDICAL EVACUATION");
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Alerted ${h['name']} via direct SMS")));
                          },
                        )
                      ],
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ---------------- 5. USER PROFILE & DETAILS SCREEN ----------------
class UserProfileDetailsScreen extends StatefulWidget {
  const UserProfileDetailsScreen({super.key});
  @override
  State<UserProfileDetailsScreen> createState() => _UserProfileDetailsScreenState();
}

class _UserProfileDetailsScreenState extends State<UserProfileDetailsScreen> {
  String _name = "Loading...";
  String _phone = "Loading...";
  String _room = "None";

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('user_name') ?? 'Trekker';
      _phone = prefs.getString('user_phone') ?? 'Not registered';
      _room = prefs.getString('current_room_code') ?? 'None';
    });
  }

  void _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginRegistrationScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF00E676), width: 2),
                ),
                child: const Icon(Icons.person, size: 70, color: Color(0xFF00E676)),
              ),
            ),
            const SizedBox(height: 14),
            Text(_name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(_phone, style: const TextStyle(fontSize: 13, color: Color(0xFF4ADE80))),
            const SizedBox(height: 24),

            // Details Container
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF10241A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1F4330)),
              ),
              child: Column(
                children: [
                  _buildProfileRow("OPERATOR NAME", _name),
                  const Divider(color: Color(0xFF1F4330)),
                  _buildProfileRow("PRIMARY CONTACT", _phone),
                  const Divider(color: Color(0xFF1F4330)),
                  _buildProfileRow("ACTIVE ROOM CODE", _room),
                  const Divider(color: Color(0xFF1F4330)),
                  _buildProfileRow("MESH PROTOCOL", "GSM / SMS BROADCAST"),
                  const Divider(color: Color(0xFF1F4330)),
                  _buildProfileRow("SECURITY STATUS", "ENCRYPTED & AUTHENTICATED"),
                ],
              ),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
                onPressed: () => _logout(context),
                label: const Text("DISCONNECT TERMINAL / LOGOUT", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, color: Color(0xFF4ADE80), fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontSize: 12, color: Colors.white)),
        ],
      ),
    );
  }
}
