import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mediasfu_mediasoup_client/mediasfu_mediasoup_client.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class MediasoupCallService {
  final io.Socket socket;
  Device? _device;
  Transport? _sendTransport;
  Transport? _recvTransport;
  Producer? _audioProducer;
  Producer? _videoProducer;
  final Map<String, Consumer> _consumers = {};

  MediaStream? localStream;
  MediaStream? remoteStream;

  Function(MediaStream)? onLocalStream;
  Function(MediaStream)? onRemoteStream;

  MediasoupCallService({required this.socket});

  // ==========================================
  // SAFE SOCKET EMITTER WITH 8-SECOND TIMEOUT
  // ==========================================
  Future<dynamic> _emitWithAck(String event, dynamic data) async {
    final completer = Completer<dynamic>();
    debugPrint("📡 Sending socket event: $event...");

    socket.emitWithAck(
      event,
      data,
      ack: (response) {
        debugPrint("✅ Received ack for: $event");
        if (!completer.isCompleted) completer.complete(response);
      },
    );

    try {
      return await completer.future.timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint("❌ TIMEOUT waiting for $event response from server!");
      throw Exception('Socket timeout on $event');
    }
  }

  // ==========================================
  // BULLETPROOF PARSERS
  // ==========================================
  Map<String, dynamic> _extractMap(dynamic data) {
    if (data is List)
      return data.isNotEmpty && data.first is Map
          ? Map<String, dynamic>.from(data.first as Map)
          : {};
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List)
      return data.isNotEmpty && data.first is List
          ? data.first as List<dynamic>
          : data;
    return [];
  }

  // ==========================================
  // MEDIASOUP CALL LOGIC
  // ==========================================
  Future<void> initCall({required bool isVideo}) async {
    try {
      debugPrint("▶️ Starting initCall...");
      remoteStream = await createLocalMediaStream('remote_stream');

      debugPrint("📷 Getting User Media...");
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideo ? {'facingMode': 'user'} : false,
      });
      debugPrint("✅ User Media Acquired!");

      if (onLocalStream != null) onLocalStream!(localStream!);

      final data = await _emitWithAck('getRouterRtpCapabilities', {});
      final routerRtpCapabilities = _extractMap(data);

      if (routerRtpCapabilities.isEmpty) {
        debugPrint("❌ SERVER SENT EMPTY CAPABILITIES! (Check Node.js server)");
        return;
      }

      debugPrint("⚙️ Loading Mediasoup Device...");
      _device = Device();
      await _device!.load(
        routerRtpCapabilities: RtpCapabilities.fromMap(routerRtpCapabilities),
      );
      debugPrint("✅ Mediasoup Device Loaded!");

      debugPrint("🚀 Creating Send Transport...");
      await _initSendTransport();

      debugPrint("📥 Creating Recv Transport...");
      await _initRecvTransport();

      debugPrint("📤 Producing Local Tracks...");
      for (var track in localStream!.getTracks()) {
        if (track.kind == 'audio') {
          _sendTransport!.produce(
            track: track,
            stream: localStream!,
            source: 'mic',
          );
        } else if (track.kind == 'video' && isVideo) {
          _sendTransport!.produce(
            track: track,
            stream: localStream!,
            source: 'webcam',
          );
        }
      }

      socket.on('newProducer', (data) async {
        final payload = _extractMap(data);
        final producerId = payload['producerId'] as String?;
        if (producerId != null) await _consumeProducer(producerId);
      });

      debugPrint("🔄 Fetching Existing Producers...");
      final producersData = await _emitWithAck('getProducers', {});
      final existingProducers = _extractList(producersData);

      for (var p in existingProducers) {
        final prodMap = _extractMap(p);
        final producerId = prodMap['producerId'] as String?;
        if (producerId != null) await _consumeProducer(producerId);
      }

      debugPrint("🎉 initCall completed successfully!");
    } catch (e, stackTrace) {
      debugPrint("❌ MEDIASOUP CRASHED: $e\n$stackTrace");
    }
  }

  Future<void> _initSendTransport() async {
    final data = await _emitWithAck('createWebRtcTransport', {});
    final transportParams = _extractMap(data);

    if (transportParams.isEmpty) return;

    _sendTransport = _device!.createSendTransportFromMap(
      transportParams,
      producerCallback: (Producer producer) {
        if (producer.track?.kind == 'audio')
          _audioProducer = producer;
        else if (producer.track?.kind == 'video')
          _videoProducer = producer;
      },
    );

    _sendTransport!.on('connect', (Map eventData) {
      debugPrint("🔗 Send Transport connecting...");
      socket.emitWithAck(
        'connectTransport',
        {
          'transportId': _sendTransport!.id,
          'dtlsParameters': (eventData['dtlsParameters'] as DtlsParameters)
              .toMap(),
        },
        ack: (res) {
          debugPrint("✅ Send Transport connected!");
          final Function callback = eventData['callback'] as Function;
          callback();
        },
      );
    });

    _sendTransport!.on('produce', (Map eventData) {
      debugPrint("🎬 Producing track: ${eventData['kind']}...");
      socket.emitWithAck(
        'produce',
        {
          'transportId': _sendTransport!.id,
          'kind': eventData['kind'],
          'rtpParameters': (eventData['rtpParameters'] as RtpParameters)
              .toMap(),
          'appData': eventData['appData'],
        },
        ack: (res) {
          debugPrint("✅ Produced track: ${eventData['kind']}!");
          final payload = _extractMap(res);
          final Function callback = eventData['callback'] as Function;
          callback(payload['id']);
        },
      );
    });
  }

  Future<void> _initRecvTransport() async {
    final data = await _emitWithAck('createWebRtcTransport', {});
    final transportParams = _extractMap(data);

    if (transportParams.isEmpty) return;

    _recvTransport = _device!.createRecvTransportFromMap(
      transportParams,
      consumerCallback: (Consumer consumer) {
        _consumers[consumer.id] = consumer;
        remoteStream!.addTrack(consumer.track);

        if (onRemoteStream != null) onRemoteStream!(remoteStream!);

        debugPrint("▶️ Resuming Consumer: ${consumer.id}...");
        socket.emit('resumeConsumer', {'consumerId': consumer.id});
      },
    );

    _recvTransport!.on('connect', (Map eventData) {
      debugPrint("🔗 Recv Transport connecting...");
      socket.emitWithAck(
        'connectTransport',
        {
          'transportId': _recvTransport!.id,
          'dtlsParameters': (eventData['dtlsParameters'] as DtlsParameters)
              .toMap(),
        },
        ack: (res) {
          debugPrint("✅ Recv Transport connected!");
          final Function callback = eventData['callback'] as Function;
          callback();
        },
      );
    });
  }

  Future<void> _consumeProducer(String producerId) async {
    debugPrint("⬇️ Consuming remote producer: $producerId...");
    final data = await _emitWithAck('consume', {
      'transportId': _recvTransport!.id,
      'producerId': producerId,
      'rtpCapabilities': _device!.rtpCapabilities.toMap(),
    });

    final consumerData = _extractMap(data);

    if (consumerData.isEmpty || consumerData.containsKey('error')) {
      debugPrint("❌ Failed to consume: $consumerData");
      return;
    }

    _recvTransport!.consume(
      id: consumerData['id'],
      producerId: consumerData['producerId'],
      peerId: 'remote-peer',
      kind: RTCRtpMediaTypeExtension.fromString(consumerData['kind']),
      rtpParameters: RtpParameters.fromMap(consumerData['rtpParameters']),
    );
    debugPrint("✅ Consumer created for: $producerId");
  }

  void endCall() {
    _audioProducer?.close();
    _videoProducer?.close();
    for (var consumer in _consumers.values) {
      consumer.close();
    }
    _consumers.clear();
    _sendTransport?.close();
    _recvTransport?.close();
    localStream?.dispose();
    remoteStream?.dispose();
    socket.off('newProducer');
  }
}
