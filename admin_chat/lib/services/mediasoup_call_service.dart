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
  // BULLETPROOF PUB/SUB REQUEST HANDLER
  // ==========================================
  Future<dynamic> _request(
    String emitEvent,
    String listenEvent,
    Map<String, dynamic> payload,
  ) async {
    final completer = Completer<dynamic>();
    final reqId = "${DateTime.now().millisecondsSinceEpoch}_$emitEvent";
    payload['reqId'] = reqId;

    debugPrint("📡 Sending $emitEvent...");

    void listener(dynamic response) {
      final res = (response is List && response.isNotEmpty)
          ? response.first
          : response;
      if (res is Map && res['reqId'] == reqId) {
        debugPrint("✅ Received $listenEvent");
        socket.off(listenEvent, listener); // Cleanup

        if (!completer.isCompleted) {
          if (res.containsKey('error')) {
            completer.completeError(res['error']);
          } else {
            completer.complete(res['data'] ?? res);
          }
        }
      }
    }

    socket.on(listenEvent, listener);
    socket.emit(emitEvent, payload);

    try {
      return await completer.future.timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint("❌ TIMEOUT on $emitEvent!");
      socket.off(listenEvent, listener); // Cleanup on timeout
      throw Exception('Socket timeout on $emitEvent');
    }
  }

  Map<String, dynamic> _extractMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty && data.first is Map)
      return Map<String, dynamic>.from(data.first);
    return {};
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
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

      final data = await _request(
        'getRouterRtpCapabilities',
        'routerRtpCapabilitiesResponse',
        {},
      );
      final routerRtpCapabilities = _extractMap(data);

      if (routerRtpCapabilities.isEmpty) return;

      debugPrint("⚙️ Loading Mediasoup Device...");
      _device = Device();
      await _device!.load(
        routerRtpCapabilities: RtpCapabilities.fromMap(routerRtpCapabilities),
      );
      debugPrint("✅ Mediasoup Device Loaded!");

      debugPrint("🚀 Creating Transports...");
      await _initSendTransport();
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
      final producersData = await _request(
        'getProducers',
        'producersListResponse',
        {},
      );
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
    final data = await _request(
      'createWebRtcTransport',
      'webRtcTransportCreated',
      {},
    );
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

    _sendTransport!.on('connect', (Map eventData) async {
      debugPrint("🔗 Send Transport connecting...");
      await _request('connectTransport', 'transportConnected', {
        'transportId': _sendTransport!.id,
        'dtlsParameters': (eventData['dtlsParameters'] as DtlsParameters)
            .toMap(),
      });
      debugPrint("✅ Send Transport connected!");
      final Function callback = eventData['callback'] as Function;
      callback();
    });

    _sendTransport!.on('produce', (Map eventData) async {
      debugPrint("🎬 Producing track: ${eventData['kind']}...");
      final res = await _request('produce', 'produced', {
        'transportId': _sendTransport!.id,
        'kind': eventData['kind'],
        'rtpParameters': (eventData['rtpParameters'] as RtpParameters).toMap(),
        'appData': eventData['appData'],
      });
      debugPrint("✅ Produced track: ${eventData['kind']}!");

      final payload = _extractMap(res);
      final Function callback = eventData['callback'] as Function;
      callback(payload['id']);
    });
  }

  Future<void> _initRecvTransport() async {
    final data = await _request(
      'createWebRtcTransport',
      'webRtcTransportCreated',
      {},
    );
    final transportParams = _extractMap(data);

    if (transportParams.isEmpty) return;

    _recvTransport = _device!.createRecvTransportFromMap(
      transportParams,
      consumerCallback: (Consumer consumer) async {
        _consumers[consumer.id] = consumer;
        remoteStream!.addTrack(consumer.track);

        if (onRemoteStream != null) onRemoteStream!(remoteStream!);

        debugPrint("▶️ Resuming Consumer: ${consumer.id}...");
        await _request('resumeConsumer', 'consumerResumed', {
          'consumerId': consumer.id,
        });
      },
    );

    _recvTransport!.on('connect', (Map eventData) async {
      debugPrint("🔗 Recv Transport connecting...");
      await _request('connectTransport', 'transportConnected', {
        'transportId': _recvTransport!.id,
        'dtlsParameters': (eventData['dtlsParameters'] as DtlsParameters)
            .toMap(),
      });
      debugPrint("✅ Recv Transport connected!");
      final Function callback = eventData['callback'] as Function;
      callback();
    });
  }

  Future<void> _consumeProducer(String producerId) async {
    debugPrint("⬇️ Consuming remote producer: $producerId...");
    final data = await _request('consume', 'consumed', {
      'transportId': _recvTransport!.id,
      'producerId': producerId,
      'rtpCapabilities': _device!.rtpCapabilities.toMap(),
    });

    final consumerData = _extractMap(data);
    if (consumerData.isEmpty) return;

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
