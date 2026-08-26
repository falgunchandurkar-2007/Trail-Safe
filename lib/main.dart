import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/mesh_service.dart';
import 'bloc/mesh_bloc.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrailSafeApp());
}

class TrailSafeApp extends StatelessWidget {
  const TrailSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrailSafe Mesh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF238636),
          error: Color(0xFFDA3633),
        ),
      ),
      home: const MeshChatScreen(),
    );
  }
}

class MeshChatScreen extends StatefulWidget {
  const MeshChatScreen({super.key});

  @override
  State<MeshChatScreen> createState() => _MeshChatScreenState();
}

class _MeshChatScreenState extends State<MeshChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final String _username = "Hiker_${DateTime.now().millisecond}";
  late MeshService _meshService;
  late MeshBloc _meshBloc;

  @override
  void initState() {
    super.initState();
    _meshService = MeshService();
    _meshBloc = MeshBloc(_meshService);
    _initPermissions();
  }

  Future<void> _initPermissions() async {
    await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    _meshBloc.add(StartMeshEvent(_username));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => _meshBloc,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF161B22),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SHARED OFFLINE MESH CHAT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              BlocBuilder<MeshBloc, MeshState>(
                builder: (context, state) {
                  int peers = (state is MeshLoadedState) ? state.peerCount : 0;
                  return Text(
                    'ACTIVE MEMBERS: $peers',
                    style: TextStyle(fontSize: 11, color: peers > 0 ? Colors.greenAccent : Colors.grey),
                  );
                },
              ),
            ],
          ),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Icon(Icons.wifi_tethering, color: Colors.greenAccent),
            )
          ],
        ),
        body: Column(
          children: [
            // Panic SOS Header Action
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF161B22),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDA3633),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.emergency_share, color: Colors.white),
                label: const Text('DISPATCH PANIC SOS TO ALL NODES', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                onPressed: () => _meshBloc.add(PanicSosEvent(_username)),
              ),
            ),

            // Tactical Messages Stream
            Expanded(
              child: BlocBuilder<MeshBloc, MeshState>(
                builder: (context, state) {
                  if (state is! MeshLoadedState) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      final item = state.messages[index];
                      final isSos = item['isSos'] == 1;
                      final isMe = item['sender'] == 'ME';

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                          decoration: BoxDecoration(
                            color: isSos
                                ? const Color(0xFF7F1D1D)
                                : (isMe ? const Color(0xFF238636) : const Color(0xFF21262D)),
                            border: Border.all(
                              color: isSos ? Colors.redAccent : Colors.green.withOpacity(0.3),
                              width: 1.2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item['sender']} ${isSos ? "(SOS)" : ""}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item['content'] ?? '',
                                style: const TextStyle(fontSize: 13, color: Colors.white),
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

            // Input Bar
            Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xFF161B22),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Broadcast over offline mesh...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        fillColor: const Color(0xFF0D1117),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.greenAccent),
                    onPressed: () {
                      if (_msgController.text.trim().isNotEmpty) {
                        _meshBloc.add(SendTextEvent(_username, _msgController.text.trim()));
                        _msgController.clear();
                      }
                    },
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
