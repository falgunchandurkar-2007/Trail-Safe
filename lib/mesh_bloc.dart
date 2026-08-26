import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'mesh_service.dart';
import 'db_helper.dart';

abstract class MeshEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class StartMeshEvent extends MeshEvent {
  final String username;
  StartMeshEvent(this.username);
}

class SendTextEvent extends MeshEvent {
  final String sender;
  final String text;
  SendTextEvent(this.sender, this.text);
}

class PanicSosEvent extends MeshEvent {
  final String sender;
  PanicSosEvent(this.sender);
}

class RefreshEvent extends MeshEvent {}

abstract class MeshState extends Equatable {
  @override
  List<Object?> get props => [];
}

class MeshInitial extends MeshState {}

class MeshLoadedState extends MeshState {
  final List<Map<String, dynamic>> messages;
  final int peerCount;
  MeshLoadedState(this.messages, this.peerCount);

  @override
  List<Object?> get props => [messages, peerCount];
}

class MeshBloc extends Bloc<MeshEvent, MeshState> {
  final MeshService meshService;

  MeshBloc(this.meshService) : super(MeshInitial()) {
    meshService.onDataUpdated = () => add(RefreshEvent());

    on<StartMeshEvent>((event, emit) async {
      await meshService.startMesh(event.username);
      final list = await DBHelper.instance.getMessages();
      emit(MeshLoadedState(list, meshService.activePeers.length));
    });

    on<SendTextEvent>((event, emit) async {
      await meshService.broadcastMessage(event.sender, event.text);
      final list = await DBHelper.instance.getMessages();
      emit(MeshLoadedState(list, meshService.activePeers.length));
    });

    on<PanicSosEvent>((event, emit) async {
      await meshService.triggerSos(event.sender);
      final list = await DBHelper.instance.getMessages();
      emit(MeshLoadedState(list, meshService.activePeers.length));
    });

    on<RefreshEvent>((event, emit) async {
      final list = await DBHelper.instance.getMessages();
      emit(MeshLoadedState(list, meshService.activePeers.length));
    });
  }
}
