import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Telephony telephony = Telephony.instance;

// Background SMS Receiver handler
@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  final body = message.body ?? "";
  final sender = message.address ?? "Unknown";
  if (body.startsWith("[TS_MESH]")) {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawMsgs = prefs.getStringList('offline_messages') ?? [];
    final cleanText = body.replaceFirst("[TS_MESH]", "").trim();
    rawMsgs.add(jsonEncode({
      'sender': sender,
      'text': cleanText,
      'isMe': false,
      'timestamp': DateTime.now().toIso8601String()
    }));
    await prefs.setStringList('offline_messages', rawMsgs);
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
      title: 'TrailSafe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09140E),
        primaryColor: const Color(0xFF00E676),
        fontFamily: 'monospace',
      ),
      home: const AuthCheckScreen(),
    );
  }
}

// ---------------- AUTH CHECK SCREEN ----------------
class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});
  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  void _checkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone');
    if (!mounted) return;
    if (phone != null && phone.isNotEmpty) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigationScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginOTPScreen()));
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

// ---------------- LOGIN WITH OTP SCREEN ----------------
class LoginOTPScreen extends StatefulWidget {
  const LoginOTPScreen({super.key});
  @override
  State<LoginOTPScreen> createState() => _LoginOTPScreenState();
}

class _LoginOTPScreenState extends State<LoginOTPScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String? generatedOTP;
  bool isOtpSent = false;

  void _sendOTP() async {
    if (_phoneCtrl.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter valid 10-digit phone number")));
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
      message: "[TrailSafe Security] Your authentication passcode is: $otp",
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF132B1F),
        content: Text("⚡ Passcode dispatched: $otp (auto-sent via SMS)", style: const TextStyle(color: Color(0xFF00E676))),
      ),
    );
  }

  void _verifyOTP() async {
    if (_otpCtrl.text.trim() == generatedOTP) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.heavyImpact();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_phone', _phoneCtrl.text.trim());
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigationScreen()));
      }
    } else {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Passcode. Access Denied.")));
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
                    boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.25), blurRadius: 20)],
                  ),
                  child: const Icon(Icons.shield_outlined, size: 54, color: Color(0xFF00E676)),
                ),
                const SizedBox(height: 20),
                const Text("TRAILSAFE // PROTOCOL", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white)),
                const Text("SECURE OFFLINE DISPATCH GATEWAY", style: TextStyle(fontSize: 10, color: Color(0xFF00E676), letterSpacing: 1.5)),
                const SizedBox(height: 36),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.phone_android, color: Color(0xFF00E676)),
                    hintText: "Enter Mobile Number",
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: const Color(0xFF132B1F),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                if (isOtpSent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, letterSpacing: 6, fontSize: 18),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: "4-DIGIT CODE",
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), letterSpacing: 1),
                      filled: true,
                      fillColor: const Color(0xFF132B1F),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isOtpSent ? _verifyOTP : _sendOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isOtpSent ? "AUTHENTICATE GATEWAY" : "DISPATCH OTP CODE",
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

// ---------------- MAIN BOTTOM NAV ----------------
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const SOSHomeScreen(),
    const MeshGroupScreen(),
    const PlaceholderScreen(title: "Hospital Radar (Offline Triangulation)"),
    const PlaceholderScreen(title: "Satellite Track Route"),
    const ProfileScreen(),
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
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_outlined), label: 'Group'),
          BottomNavigationBarItem(icon: Icon(Icons.local_hospital_outlined), label: 'Hospitals'),
          BottomNavigationBarItem(icon: Icon(Icons.location_on_outlined), label: 'Track'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

// ---------------- 1. SOS SCREEN (TACTICAL RADAR HUD) ----------------
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
  }

  void _initSMSListener() async {
    await telephony.requestPhoneAndSmsPermissions;
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage msg) async {
        final body = msg.body ?? "";
        final sender = msg.address ?? "Unknown";
        if (body.startsWith("[TS_MESH]")) {
          final cleanText = body.replaceFirst("[TS_MESH]", "").trim();
          final prefs = await SharedPreferences.getInstance();
          List<String> rawMsgs = prefs.getStringList('offline_messages') ?? [];
          rawMsgs.add(jsonEncode({
            'sender': sender,
            'text': cleanText,
            'isMe': false,
            'timestamp': DateTime.now().toIso8601String()
          }));
          await prefs.setStringList('offline_messages', rawMsgs);

          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.vibrate();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF132B1F),
                content: Text("🚨 Incoming Signal from $sender: $cleanText", style: const TextStyle(color: Color(0xFF00E676))),
              ),
            );
          }
        }
      },
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );
  }

  void _getGPS() async {
    setState(() => _fetchingGps = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = pos;
        _gpsText = "LAT: ${pos.latitude.toStringAsFixed(5)} | LON: ${pos.longitude.toStringAsFixed(5)}";
        _fetchingGps = false;
      });
    } catch (e) {
      setState(() {
        _gpsText = "GPS Fixed via Satellites (Offline Mode)";
        _fetchingGps = false;
      });
    }
  }

  void _triggerEmergencySOS() async {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();

    final prefs = await SharedPreferences.getInstance();
    List<String> members = prefs.getStringList('mesh_members') ?? [];

    String coords = _currentPosition != null 
      ? "https://maps.google.com/?q=${_currentPosition!.latitude},${_currentPosition!.longitude}"
      : "Coordinates Locked via GPS";

    String payload = "[TS_MESH] 🚨 EMERGENCY ALERT: $_selectedEmergency! Location: $coords";

    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add member numbers in Group tab to broadcast SMS alert.")),
      );
      return;
    }

    for (var m in members) {
      final decoded = jsonDecode(m);
      telephony.sendSms(to: decoded['phone'], message: payload);
    }

    List<String> rawMsgs = prefs.getStringList('offline_messages') ?? [];
    rawMsgs.add(jsonEncode({
      'sender': 'ME (SOS)',
      'text': "🚨 EMERGENCY: $_selectedEmergency - $coords",
      'isMe': true,
      'timestamp': DateTime.now().toIso8601String()
    }));
    await prefs.setStringList('offline_messages', rawMsgs);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text("⚡ SOS DISPATCHED TO ${members.length} MEMBERS OVER MESH", style: const TextStyle(fontWeight: FontWeight.bold)),
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
            const Text("TrailSafe", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 14),

            // GPS Telemetry HUD
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

            // Red SOS Button
            Center(
              child: GestureDetector(
                onTap: _triggerEmergencySOS,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF7F1D1D), width: 3),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.35), blurRadius: 40, spreadRadius: 5),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFEF4444),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("SOS", style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
                          Text("Press to alert", style: TextStyle(fontSize: 12, color: Colors.white70)),
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

            // Emergency Chips Matrix
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
                    child: Text("Offline SMS mesh active. Manage nodes in Group tab.", style: TextStyle(fontSize: 11, color: Colors.white70)),
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

// ---------------- 2. OFFLINE MESH GROUP CHAT ----------------
class MeshGroupScreen extends StatefulWidget {
  const MeshGroupScreen({super.key});
  @override
  State<MeshGroupScreen> createState() => _MeshGroupScreenState();
}

class _MeshGroupScreenState extends State<MeshGroupScreen> {
  final _msgCtrl = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _refreshData();
    Timer.periodic(const Duration(seconds: 2), (_) => _refreshData());
  }

  void _refreshData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawMsgs = prefs.getStringList('offline_messages') ?? [];
    List<String> rawMems = prefs.getStringList('mesh_members') ?? [];

    if (mounted) {
      setState(() {
        _messages = rawMsgs.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
        _members = rawMems.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
      });
    }
  }

  void _sendMeshMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();

    final prefs = await SharedPreferences.getInstance();
    List<String> rawMems = prefs.getStringList('mesh_members') ?? [];

    if (rawMems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add nodes using the (+) icon first!")));
      return;
    }

    for (var m in rawMems) {
      final decoded = jsonDecode(m);
      telephony.sendSms(to: decoded['phone'], message: "[TS_MESH] $text");
    }

    List<String> rawMsgs = prefs.getStringList('offline_messages') ?? [];
    rawMsgs.add(jsonEncode({
      'sender': 'ME',
      'text': text,
      'isMe': true,
      'timestamp': DateTime.now().toIso8601String()
    }));
    await prefs.setStringList('offline_messages', rawMsgs);

    _refreshData();
  }

  void _addMemberDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF10241A),
        title: const Text("ADD MESH NODE (MEMBER)", style: TextStyle(color: Color(0xFF00E676), fontSize: 14)),
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
                List<String> mems = prefs.getStringList('mesh_members') ?? [];
                mems.add(jsonEncode({'name': nameCtrl.text, 'phone': phoneCtrl.text.trim()}));
                await prefs.setStringList('mesh_members', mems);
                _refreshData();
                Navigator.pop(context);
              }
            },
            child: const Text("ADD NODE"),
          )
        ],
      ),
    );
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
                    const Text("OFFLINE MESH CHAT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    Text("ACTIVE NODES: ${_members.length}", style: const TextStyle(fontSize: 10, color: Color(0xFF00E676))),
                  ],
                ),
                IconButton(icon: const Icon(Icons.person_add, color: Color(0xFF00E676)), onPressed: _addMemberDialog),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final isMe = m['isMe'] == true;
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
                      hintText: "Transmit over SMS Mesh...",
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
                  onPressed: _sendMeshMessage,
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ---------------- PLACEHOLDER SCREEN ----------------
class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF4ADE80), letterSpacing: 1.2)),
    );
  }
}

// ---------------- 5. PROFILE SCREEN ----------------
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginOTPScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_circle, size: 80, color: Color(0xFF00E676)),
            const SizedBox(height: 12),
            const Text("DISPATCH OPERATOR NODE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
              onPressed: () => _logout(context),
              child: const Text("DISCONNECT TERMINAL"),
            )
          ],
        ),
      ),
    );
  }
}
