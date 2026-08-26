import 'dart:convert';
import 'dart:typed_data';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:geolocator/geolocator.dart';
import 'db_helper.dart';
import 'sound_service.dart';

class MeshService {
  static final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = "com.trailsafe.mesh";
  
  // Tracks every single active node in the room
  final Set<String> activePeers = {};

  Function()? onDataUpdated;

  Future<void> startMesh(String username) async {
    try {
      await Nearby().startAdvertising(
        username,
        strategy,
        onConnectionInitiated: (endpointId, info) async {
          await Nearby().acceptConnection(
            endpointId,
            onPayLoadRecieved: (endpointId, payload) {
              if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                _handlePayload(payload.bytes!);
              }
            },
          );
        },
        onConnectionResult: (endpointId, status) {
          if (status == Status.CONNECTED) {
            activePeers.add(endpointId);
          } else {
            activePeers.remove(endpointId);
          }
          if (onDataUpdated != null) onDataUpdated!();
        },
        onDisconnected: (endpointId) {
          activePeers.remove(endpointId);
          if (onDataUpdated != null) onDataUpdated!();
        },
        serviceId: serviceId,
      );

      await Nearby().startDiscovery(
        username,
        strategy,
        onEndpointFound: (endpointId, name, serviceId) async {
          try {
            await Nearby().requestConnection(
              username,
              endpointId,
              onConnectionInitiated: (endpointId, info) async {
                await Nearby().acceptConnection(
                  endpointId,
                  onPayLoadRecieved: (endpointId, payload) {
                    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                      _handlePayload(payload.bytes!);
                    }
                  },
                );
              },
              onConnectionResult: (endpointId, status) {
                if (status == Status.CONNECTED) {
                  activePeers.add(endpointId);
                } else {
                  activePeers.remove(endpointId);
                }
                if (onDataUpdated != null) onDataUpdated!();
              },
              onDisconnected: (endpointId) {
                activePeers.remove(endpointId);
                if (onDataUpdated != null) onDataUpdated!();
              },
            );
          } catch (_) {}
        },
        onEndpointLost: (endpointId) {
          activePeers.remove(endpointId);
          if (onDataUpdated != null) onDataUpdated!();
        },
        serviceId: serviceId,
      );
    } catch (_) {}
  }

  void _handlePayload(Uint8List bytes) async {
    final raw = utf8.decode(bytes);
    final data = jsonDecode(raw) as Map<String, dynamic>;

    final sender = data['sender'] ?? 'Unknown';
    final content = data['content'] ?? '';
    final isSos = data['isSos'] == true;

    if (isSos) {
      SoundService.playSosAlarm();
    } else {
      SoundService.playMessageBeep();
    }

    await DBHelper.instance.insertMessage({
      'sender': sender,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'isSos': isSos ? 1 : 0,
    });

    if (onDataUpdated != null) onDataUpdated!();
  }

  // Sends strictly via P2P Mesh to all discovered peers
  Future<void> broadcastMessage(String sender, String content, {bool isSos = false}) async {
    final payloadMap = {
      'sender': sender,
      'content': content,
      'isSos': isSos,
      'timestamp': DateTime.now().toIso8601String(),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payloadMap)));

    for (final peerId in activePeers) {
      try {
        await Nearby().sendBytesPayload(peerId, bytes);
      } catch (_) {}
    }

    await DBHelper.instance.insertMessage({
      'sender': 'ME',
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'isSos': isSos ? 1 : 0,
    });

    if (onDataUpdated != null) onDataUpdated!();
  }

  // Locks satellite coordinates and alerts all nodes
  Future<void> triggerSos(String username) async {
    Position pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    final sosText = "🚨 EMERGENCY DISPATCH: Injury (https://maps.google.com/?q=${pos.latitude},${pos.longitude})";
    
    SoundService.playSosAlarm();
    await broadcastMessage(username, sosText, isSos: true);
  }
}
