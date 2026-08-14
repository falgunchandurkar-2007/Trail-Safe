import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';

// Native Android Background Message Interceptor
@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) {}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrailSafeApp());
}

// =============================================================================
// 1. DATA MODELS & PROTOCOL
// =============================================================================
enum UserRole { leader, member }

class TeamMember extends Equatable {
  final String name;
  final String phone;
  final UserRole role;

  const TeamMember(
      {required this.name, required this.phone, required this.role});

  @override
  List<Object?> get props => [name, phone, role];
}

class InAppMessage extends Equatable {
  final String senderName;
  final UserRole senderRole;
  final String senderPhone;
  final String content;
  final double? latitude;
  final double? longitude;
  final bool isSOS;
  final DateTime timestamp;
  final bool isMe;

  const InAppMessage({
    required this.senderName,
    required this.senderRole,
    required this.senderPhone,
    required this.content,
    this.latitude,
    this.longitude,
    this.isSOS = false,
    required this.timestamp,
    this.isMe = false,
  });

  @override
  List<Object?> get props => [
        senderName,
        senderRole,
        senderPhone,
        content,
        latitude,
        longitude,
        isSOS,
        timestamp,
        isMe
      ];
}

class SoundFX {
  static void tap() {
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  static void send() {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }

  static void sosAlert() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }
}

// =============================================================================
// 2. STATE MANAGEMENT (BLoC)
// =============================================================================
abstract class AppEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class InitHardwareEvent extends AppEvent {}

class CreateGroupEvent extends AppEvent {
  final String name;
  final String phone;
  final String groupCode;

  CreateGroupEvent(
      {required this.name, required this.phone, required this.groupCode});
}

class JoinGroupEvent extends AppEvent {
  final String name;
  final String phone;
  final String leaderPhone;
  final String groupCode;

  JoinGroupEvent(
      {required this.name,
      required this.phone,
      required this.leaderPhone,
      required this.groupCode});
}

class SendMessageEvent extends AppEvent {
  final String text;
  final bool isSOS;

  SendMessageEvent({required this.text, this.isSOS = false});
}

class IncomingCellularPayloadEvent extends AppEvent {
  final String rawBody;
  final String senderAddress;

  IncomingCellularPayloadEvent(
      {required this.rawBody, required this.senderAddress});
}

class AppState extends Equatable {
  final bool isInGroup;
  final String myName;
  final String myPhone;
  final UserRole myRole;
  final String groupCode;
  final List<TeamMember> activeGroup;
  final List<InAppMessage> chatFeed;
  final Position? gpsPosition;
  final String toastMessage;

  const AppState({
    this.isInGroup = false,
    this.myName = '',
    this.myPhone = '',
    this.myRole = UserRole.member,
    this.groupCode = '',
    this.activeGroup = const [],
    this.chatFeed = const [],
    this.gpsPosition,
    this.toastMessage = '',
  });

  AppState copyWith({
    bool? isInGroup,
    String? myName,
    String? myPhone,
    UserRole? myRole,
    String? groupCode,
    List<TeamMember>? activeGroup,
    List<InAppMessage>? chatFeed,
    Position? gpsPosition,
    String? toastMessage,
  }) {
    return AppState(
      isInGroup: isInGroup ?? this.isInGroup,
      myName: myName ?? this.myName,
      myPhone: myPhone ?? this.myPhone,
      myRole: myRole ?? this.myRole,
      groupCode: groupCode ?? this.groupCode,
      activeGroup: activeGroup ?? this.activeGroup,
      chatFeed: chatFeed ?? this.chatFeed,
      gpsPosition: gpsPosition ?? this.gpsPosition,
      toastMessage: toastMessage ?? this.toastMessage,
    );
  }

  @override
  List<Object?> get props => [
        isInGroup,
        myName,
        myPhone,
        myRole,
        groupCode,
        activeGroup,
        chatFeed,
        gpsPosition,
        toastMessage
      ];
}

class AppBloc extends Bloc<AppEvent, AppState> {
  final Telephony _telephony = Telephony.instance;

  AppBloc() : super(const AppState()) {
    on<InitHardwareEvent>(_onInitHardware);
    on<CreateGroupEvent>(_onCreateGroup);
    on<JoinGroupEvent>(_onJoinGroup);
    on<SendMessageEvent>(_onSendMessage);
    on<IncomingCellularPayloadEvent>(_onIncomingCellularPayload);
  }

  Future<void> _onInitHardware(
      InitHardwareEvent event, Emitter<AppState> emit) async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        emit(state.copyWith(gpsPosition: pos));
      }
    } catch (_) {}

    if (!kIsWeb) {
      try {
        final bool? granted = await _telephony.requestPhoneAndSmsPermissions;
        if (granted == true) {
          _telephony.listenIncomingSms(
            onNewMessage: (SmsMessage msg) {
              if (msg.body != null && msg.body!.startsWith("[TRAILSAFE]")) {
                add(IncomingCellularPayloadEvent(
                    rawBody: msg.body!, senderAddress: msg.address ?? ''));
              }
            },
            onBackgroundMessage: backgroundMessageHandler,
            listenInBackground: true,
          );
        }
      } catch (_) {}
    }
  }

  void _onCreateGroup(CreateGroupEvent event, Emitter<AppState> emit) {
    SoundFX.tap();
    final leader =
        TeamMember(name: event.name, phone: event.phone, role: UserRole.leader);
    emit(state.copyWith(
      isInGroup: true,
      myName: event.name,
      myPhone: event.phone,
      myRole: UserRole.leader,
      groupCode: event.groupCode,
      activeGroup: [leader],
      toastMessage: "Lobby #${event.groupCode} Active (Offline GSM)",
    ));
  }

  Future<void> _onJoinGroup(
      JoinGroupEvent event, Emitter<AppState> emit) async {
    SoundFX.tap();
    final me =
        TeamMember(name: event.name, phone: event.phone, role: UserRole.member);
    final leader = TeamMember(
        name: "Leader", phone: event.leaderPhone, role: UserRole.leader);

    emit(state.copyWith(
      isInGroup: true,
      myName: event.name,
      myPhone: event.phone,
      myRole: UserRole.member,
      groupCode: event.groupCode,
      activeGroup: [leader, me],
      toastMessage: "Joined Group #${event.groupCode}!",
    ));

    // Send GSM Handshake Packet to Leader's SIM
    if (!kIsWeb) {
      final packet =
          "[TRAILSAFE]|${event.groupCode}|JOIN|${event.name}|${event.phone}";
      try {
        await _telephony.sendSms(to: event.leaderPhone, message: packet);
      } catch (_) {}
    }
  }

  Future<void> _onSendMessage(
      SendMessageEvent event, Emitter<AppState> emit) async {
    if (event.isSOS)
      SoundFX.sosAlert();
    else
      SoundFX.send();

    final lat = state.gpsPosition?.latitude ?? 18.5204;
    final lon = state.gpsPosition?.longitude ?? 73.8567;

    // GSM SMS Payload Structure: [TRAILSAFE]|GROUP_CODE|MSG|ROLE|NAME|PHONE|LAT|LON|IS_SOS|TEXT
    final packet =
        "[TRAILSAFE]|${state.groupCode}|MSG|${state.myRole.name}|${state.myName}|${state.myPhone}|$lat|$lon|${event.isSOS ? '1' : '0'}|${event.text}";

    // Dispatch direct SMS to all active squad SIM cards
    if (!kIsWeb) {
      for (var member in state.activeGroup) {
        if (member.phone != state.myPhone) {
          try {
            await _telephony.sendSms(to: member.phone, message: packet);
          } catch (_) {}
        }
      }
    }

    final newMsg = InAppMessage(
      senderName: "${state.myName} (You)",
      senderRole: state.myRole,
      senderPhone: state.myPhone,
      content: event.text,
      latitude: lat,
      longitude: lon,
      isSOS: event.isSOS,
      timestamp: DateTime.now(),
      isMe: true,
    );

    emit(state.copyWith(
      chatFeed: [newMsg, ...state.chatFeed],
      toastMessage: event.isSOS
          ? "🚨 SOS Broadcast Dispatched via GSM!"
          : "Cellular Packet Transmitted",
    ));
  }

  void _onIncomingCellularPayload(
      IncomingCellularPayloadEvent event, Emitter<AppState> emit) {
    try {
      final parts = event.rawBody.split('|');
      if (parts.length < 3) return;

      final groupCode = parts[1];
      final packetType = parts[2];

      if (state.isInGroup && groupCode != state.groupCode) return;

      if (packetType == 'JOIN' && state.myRole == UserRole.leader) {
        final memberName = parts[3];
        final memberPhone = parts[4];
        final newMem = TeamMember(
            name: memberName, phone: memberPhone, role: UserRole.member);

        if (!state.activeGroup.any((m) => m.phone == memberPhone)) {
          emit(state.copyWith(
            activeGroup: [...state.activeGroup, newMem],
            toastMessage: "🟢 $memberName joined via GSM!",
          ));
        }
      } else if (packetType == 'MSG') {
        final role = parts[3] == 'leader' ? UserRole.leader : UserRole.member;
        final senderName = parts[4];
        final senderPhone = parts[5];
        final lat = double.tryParse(parts[6]);
        final lon = double.tryParse(parts[7]);
        final isSOS = parts[8] == '1';
        final text = parts[9];

        if (senderPhone != state.myPhone) {
          if (isSOS)
            SoundFX.sosAlert();
          else
            SoundFX.send();

          final incoming = InAppMessage(
            senderName: senderName,
            senderRole: role,
            senderPhone: senderPhone,
            content: text,
            latitude: lat,
            longitude: lon,
            isSOS: isSOS,
            timestamp: DateTime.now(),
            isMe: false,
          );

          emit(state.copyWith(
            chatFeed: [incoming, ...state.chatFeed],
            toastMessage: isSOS
                ? "🚨 SOS FROM $senderName!"
                : "GSM Message from $senderName",
          ));
        }
      }
    } catch (_) {}
  }
}

// =============================================================================
// 3. UI VIEWS (WHATSAPP STYLE INTERFACE)
// =============================================================================
class TrailSafeApp extends StatelessWidget {
  const TrailSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppBloc()..add(InitHardwareEvent()),
      child: MaterialApp(
        title: 'TrailSafe Mesh',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0D1418),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1F2C34)),
          colorSchemeSeed: const Color(0xFF00A884),
          useMaterial3: true,
        ),
        home: BlocBuilder<AppBloc, AppState>(
          builder: (context, state) {
            return state.isInGroup
                ? const MainTacticalScreen()
                : const LobbySetupScreen();
          },
        ),
      ),
    );
  }
}

class LobbySetupScreen extends StatefulWidget {
  const LobbySetupScreen({super.key});

  @override
  State<LobbySetupScreen> createState() => _LobbySetupScreenState();
}

class _LobbySetupScreenState extends State<LobbySetupScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _leaderPhoneCtrl = TextEditingController();

  final String _roomCode = "2721";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00A884).withOpacity(0.15),
                    border:
                        Border.all(color: const Color(0xFF00A884), width: 2),
                  ),
                  child: const Icon(Icons.cell_tower,
                      size: 48, color: Color(0xFF00A884)),
                ),
              ),
              const SizedBox(height: 12),
              const Text("TRAILSAFE : OFFLINE GSM MESH",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2)),
              const Text("100% Offline Cellular SIM Network Protocol",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 24),

              // PROFILE CARD
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFF1F2C34),
                    borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("STEP 1: OPERATOR PROFILE",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00A884))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                            labelText: "Your Full Name",
                            border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                            labelText: "Phone Number (+91...)",
                            border: OutlineInputBorder())),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // CREATE ROOM (LEADER)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFF1F2C34),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.5))),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("HOST GROUP (LEADER)",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text("CODE: $_roomCode",
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.orangeAccent)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44)),
                      icon: const Icon(Icons.shield),
                      label: const Text("CREATE AS LEADER 👑"),
                      onPressed: () {
                        if (_nameCtrl.text.isNotEmpty &&
                            _phoneCtrl.text.isNotEmpty) {
                          context.read<AppBloc>().add(CreateGroupEvent(
                              name: _nameCtrl.text.trim(),
                              phone: _phoneCtrl.text.trim(),
                              groupCode: _roomCode));
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // JOIN ROOM (MEMBER)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFF1F2C34),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF00A884).withOpacity(0.5))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("JOIN GROUP (MEMBER)",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00A884))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                            labelText: "Room Code (e.g. 2721)",
                            border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _leaderPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                            labelText: "Leader's SIM Number (+91...)",
                            border: OutlineInputBorder())),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00A884),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44)),
                      icon: const Icon(Icons.group_add),
                      label: const Text("JOIN VIA GSM 🚶"),
                      onPressed: () {
                        if (_nameCtrl.text.isNotEmpty &&
                            _phoneCtrl.text.isNotEmpty &&
                            _codeCtrl.text.isNotEmpty &&
                            _leaderPhoneCtrl.text.isNotEmpty) {
                          context.read<AppBloc>().add(JoinGroupEvent(
                                name: _nameCtrl.text.trim(),
                                phone: _phoneCtrl.text.trim(),
                                leaderPhone: _leaderPhoneCtrl.text.trim(),
                                groupCode: _codeCtrl.text.trim().toUpperCase(),
                              ));
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainTacticalScreen extends StatefulWidget {
  const MainTacticalScreen({super.key});

  @override
  State<MainTacticalScreen> createState() => _MainTacticalScreenState();
}

class _MainTacticalScreenState extends State<MainTacticalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: 1);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AppBloc, AppState>(
      listener: (context, state) {
        if (state.toastMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.toastMessage),
              backgroundColor: state.toastMessage.contains("🚨")
                  ? Colors.red
                  : const Color(0xFF1F2C34),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      builder: (context, state) {
        final isLeader = state.myRole == UserRole.leader;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("LOBBY #${state.groupCode}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                    "${state.myName} (${isLeader ? 'LEADER 👑' : 'MEMBER 🚶'})",
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            bottom: TabBar(
              controller: _tab,
              indicatorColor: const Color(0xFF00A884),
              tabs: const [
                Tab(icon: Icon(Icons.emergency), text: "SOS Core"),
                Tab(icon: Icon(Icons.forum), text: "Common Chat"),
                Tab(icon: Icon(Icons.people), text: "Active Mesh"),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: [
              // TAB 1: SOS
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        context.read<AppBloc>().add(SendMessageEvent(
                            text:
                                "CRITICAL PANIC SOS TRIGGERED! IMMEDIATE ASSISTANCE REQUIRED!",
                            isSOS: true));
                      },
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red.shade700,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.red.withOpacity(0.5),
                                blurRadius: 35,
                                spreadRadius: 10)
                          ],
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning, size: 48, color: Colors.white),
                            Text("PANIC SOS",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text("QUICK EMERGENCY DISPATCH",
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.flash_on,
                              size: 14, color: Colors.redAccent),
                          label: const Text("Medical Injury 🚑"),
                          onPressed: () => context.read<AppBloc>().add(
                              SendMessageEvent(
                                  text: "Medical injury reported!",
                                  isSOS: true)),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.flash_on,
                              size: 14, color: Colors.redAccent),
                          label: const Text("Snake Bite 🐍"),
                          onPressed: () => context.read<AppBloc>().add(
                              SendMessageEvent(
                                  text: "Snake bite reported!", isSOS: true)),
                        ),
                      ],
                    )
                  ],
                ),
              ),

              // TAB 2: COMMON CHAT
              Column(
                children: [
                  Expanded(
                    child: state.chatFeed.isEmpty
                        ? Center(
                            child: Text(
                                "Offline Cellular Frequency Open for Lobby #${state.groupCode}.\nMessages transmit via carrier SMS.",
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(14),
                            itemCount: state.chatFeed.length,
                            itemBuilder: (context, index) {
                              final msg = state.chatFeed[index];
                              return Align(
                                alignment: msg.isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              0.78),
                                  decoration: BoxDecoration(
                                    color: msg.isSOS
                                        ? Colors.red.shade900
                                        : (msg.isMe
                                            ? const Color(0xFF005C4B)
                                            : const Color(0xFF202C33)),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(12),
                                      topRight: const Radius.circular(12),
                                      bottomLeft:
                                          Radius.circular(msg.isMe ? 12 : 0),
                                      bottomRight:
                                          Radius.circular(msg.isMe ? 0 : 12),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (!msg.isMe) ...[
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(msg.senderName,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                    color: Color(0xFF53BDEB))),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 1),
                                              decoration: BoxDecoration(
                                                color: msg.senderRole ==
                                                        UserRole.leader
                                                    ? Colors.orange
                                                    : Colors.blueGrey,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                  msg.senderRole ==
                                                          UserRole.leader
                                                      ? "LEADER 👑"
                                                      : "MEMBER",
                                                  style: const TextStyle(
                                                      fontSize: 8,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            )
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                      ],
                                      Text(msg.content,
                                          style: const TextStyle(fontSize: 14)),
                                      if (msg.latitude != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                            "GPS: ${msg.latitude!.toStringAsFixed(4)}, ${msg.longitude!.toStringAsFixed(4)}",
                                            style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.greenAccent)),
                                      ]
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    color: const Color(0xFF1F2C34),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            decoration: const InputDecoration(
                                hintText: "Transmit cellular message...",
                                border: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 10)),
                          ),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.send, color: Color(0xFF00A884)),
                          onPressed: () {
                            if (_input.text.trim().isNotEmpty) {
                              context.read<AppBloc>().add(
                                  SendMessageEvent(text: _input.text.trim()));
                              _input.clear();
                            }
                          },
                        )
                      ],
                    ),
                  )
                ],
              ),

              // TAB 3: ACTIVE MESH SQUAD
              ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: state.activeGroup.length,
                itemBuilder: (context, index) {
                  final member = state.activeGroup[index];
                  final isL = member.role == UserRole.leader;
                  return Card(
                    color: const Color(0xFF1F2C34),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            isL ? Colors.orange : const Color(0xFF00A884),
                        child: Icon(isL ? Icons.shield : Icons.person,
                            color: Colors.white),
                      ),
                      title: Text(member.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("SIM: ${member.phone}"),
                      trailing: Chip(
                        label: Text(isL ? "LEADER 👑" : "MEMBER 🚶",
                            style: const TextStyle(fontSize: 10)),
                        backgroundColor: isL
                            ? Colors.orange.withOpacity(0.2)
                            : const Color(0xFF00A884).withOpacity(0.2),
                      ),
                    ),
                  );
                },
              )
            ],
          ),
        );
      },
    );
  }
}
