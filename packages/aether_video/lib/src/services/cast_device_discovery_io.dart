import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';

import '../models/cast_device.dart';

/// Discovers Google Cast (Chromecast) receivers on the local network
/// (`_googlecast._tcp`). No Cast SDK.
///
/// On iOS the scan runs through the plugin's native side using the system
/// Bonjour browser (`NWBrowser`): sending raw multicast UDP from Dart needs
/// the restricted `com.apple.developer.networking.multicast` entitlement on
/// physical devices, while Bonjour browsing is exempt. Everywhere else the
/// scan is pure-Dart mDNS.
///
/// Real-device requirements (iOS 14+):
/// - The phone must be on the SAME Wi-Fi as the Cast devices.
/// - Info.plist needs `NSLocalNetworkUsageDescription` and
///   `NSBonjourServices` containing `_googlecast._tcp`.
/// - The user must accept the Local Network permission prompt (first scan
///   triggers it; after a denial: Settings > Privacy & Security > Local
///   Network).
///
/// ```xml
/// <key>NSLocalNetworkUsageDescription</key>
/// <string>Used to find Cast devices on your network.</string>
/// <key>NSBonjourServices</key>
/// <array><string>_googlecast._tcp</string></array>
/// ```
class CastDeviceDiscovery {
  CastDeviceDiscovery._();

  static const String _service = '_googlecast._tcp.local';

  static const MethodChannel _channel = MethodChannel('native_video_player');

  /// One-shot scan; resolves after [timeout] with every device seen.
  ///
  /// Throws [CastDiscoveryException] when the network blocks the scan
  /// (wrong network / missing Local Network permission) instead of leaking
  /// raw [SocketException]s — including ones the mDNS client raises from
  /// its internal retry timers, which would otherwise crash as unhandled.
  static Future<List<CastDevice>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (Platform.isIOS) return _discoverViaBonjour(timeout);
    // multicast_dns re-sends queries from internal timers; their failures
    // surface OUTSIDE the caller's await chain. The guarded zone catches
    // those strays so a denied permission can't crash the app.
    final completer = Completer<List<CastDevice>>();
    runZonedGuarded(
      () async {
        try {
          final devices = await _discover(timeout: timeout);
          if (!completer.isCompleted) completer.complete(devices);
        } catch (e, s) {
          if (!completer.isCompleted) {
            completer.completeError(_wrap(e), s);
          }
        }
      },
      (error, stack) {
        if (!completer.isCompleted) {
          completer.completeError(_wrap(error), stack);
        }
        // Late stray errors after completion are intentionally swallowed —
        // the scan outcome has already been delivered.
      },
    );
    return completer.future;
  }

  /// iOS: scan through the plugin's native NWBrowser (system Bonjour).
  static Future<List<CastDevice>> _discoverViaBonjour(Duration timeout) async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>(
        'discoverCastDevices',
        <String, dynamic>{'timeoutMs': timeout.inMilliseconds},
      );
      return (raw ?? const <dynamic>[])
          .cast<Map<dynamic, dynamic>>()
          .map(
            (m) => CastDevice(
              id: m['id'] as String,
              name: m['name'] as String,
              friendlyName: m['friendlyName'] as String?,
              model: m['model'] as String?,
              host: m['host'] as String,
              port: m['port'] as int,
            ),
          )
          .toList();
    } on PlatformException catch (e) {
      throw CastDiscoveryException(
        'Cast device scan failed (${e.message ?? e.code}). Check that the '
        'device is on the same Wi-Fi as the Cast devices and that the Local '
        'Network permission is granted (iOS: Settings > Privacy & Security > '
        'Local Network).',
        e,
      );
    } on MissingPluginException catch (e) {
      throw CastDiscoveryException(
        'The running iOS app was built before cast discovery was added — '
        'rebuild the app (full build, not hot reload).',
        e,
      );
    }
  }

  static Object _wrap(Object error) {
    if (error is SocketException) {
      return CastDiscoveryException(
        'Could not send the mDNS query (${error.osError?.message ?? error.message}). '
        'Check that the device is on the same Wi-Fi as the Cast devices and '
        'that the Local Network permission is granted '
        '(iOS: Settings > Privacy & Security > Local Network).',
        error,
      );
    }
    return error;
  }

  static Future<List<CastDevice>> _discover({required Duration timeout}) async {
    final client = MDnsClient(
      rawDatagramSocketFactory: (
        dynamic host,
        int port, {
        bool? reuseAddress,
        bool? reusePort,
        int? ttl,
      }) async {
        final socket = await RawDatagramSocket.bind(
          host,
          port,
          reuseAddress: reuseAddress ?? true,
          reusePort: Platform.isWindows ? false : (reusePort ?? true),
          ttl: ttl ?? 1,
        );
        return Platform.isWindows ? _SafeDatagramSocket(socket) : socket;
      },
    );
    final found = <String, CastDevice>{};
    await client.start();
    try {
      await for (final PtrResourceRecord ptr
          in client
              .lookup<PtrResourceRecord>(
                ResourceRecordQuery.serverPointer(_service),
              )
              .timeout(timeout, onTimeout: (sink) => sink.close())) {
        final instance = ptr.domainName;

        String host = '';
        var port = 8009;
        await for (final SrvResourceRecord srv
            in client
                .lookup<SrvResourceRecord>(
                  ResourceRecordQuery.service(instance),
                )
                .timeout(
                  const Duration(seconds: 2),
                  onTimeout: (sink) => sink.close(),
                )) {
          host = srv.target;
          port = srv.port;
          break;
        }
        if (host.isEmpty) continue;

        // Prefer a resolved IPv4 over the .local hostname when available.
        await for (final IPAddressResourceRecord ip
            in client
                .lookup<IPAddressResourceRecord>(
                  ResourceRecordQuery.addressIPv4(host),
                )
                .timeout(
                  const Duration(seconds: 2),
                  onTimeout: (sink) => sink.close(),
                )) {
          host = ip.address.address;
          break;
        }

        String? friendlyName;
        String? model;
        await for (final TxtResourceRecord txt
            in client
                .lookup<TxtResourceRecord>(ResourceRecordQuery.text(instance))
                .timeout(
                  const Duration(seconds: 2),
                  onTimeout: (sink) => sink.close(),
                )) {
          for (final line in txt.text.split('\n')) {
            final eq = line.indexOf('=');
            if (eq == -1) continue;
            final key = line.substring(0, eq).trim();
            final value = line.substring(eq + 1).trim();
            if (key == 'fn') friendlyName = value;
            if (key == 'md') model = value;
          }
          break;
        }

        final name = instance.endsWith('.$_service')
            ? instance.substring(0, instance.length - _service.length - 1)
            : instance;
        found[instance] = CastDevice(
          id: instance,
          name: name,
          friendlyName: friendlyName,
          model: model,
          host: host,
          port: port,
        );
      }
    } finally {
      client.stop();
    }
    return found.values.toList();
  }
}

/// A wrapper around [RawDatagramSocket] that safely ignores Windows-specific
/// socket errors when joining multicast groups on network interfaces that do
/// not support IP multicasting (e.g. Wi-Fi Direct virtual adapters).
class _SafeDatagramSocket extends StreamView<RawSocketEvent>
    implements RawDatagramSocket {
  final RawDatagramSocket _inner;

  _SafeDatagramSocket(this._inner) : super(_inner);

  @override
  InternetAddress get address => _inner.address;

  @override
  int get port => _inner.port;

  @override
  bool get broadcastEnabled => _inner.broadcastEnabled;

  @override
  set broadcastEnabled(bool value) => _inner.broadcastEnabled = value;

  @override
  bool get multicastLoopback => _inner.multicastLoopback;

  @override
  set multicastLoopback(bool value) => _inner.multicastLoopback = value;

  @override
  int get multicastHops => _inner.multicastHops;

  @override
  set multicastHops(int value) => _inner.multicastHops = value;

  @override
  // ignore: deprecated_member_use
  NetworkInterface? get multicastInterface => _inner.multicastInterface;

  @override
  // ignore: deprecated_member_use
  set multicastInterface(NetworkInterface? value) =>
      // ignore: deprecated_member_use
      _inner.multicastInterface = value;

  @override
  bool get readEventsEnabled => _inner.readEventsEnabled;

  @override
  set readEventsEnabled(bool value) => _inner.readEventsEnabled = value;

  @override
  bool get writeEventsEnabled => _inner.writeEventsEnabled;

  @override
  set writeEventsEnabled(bool value) => _inner.writeEventsEnabled = value;

  @override
  void close() => _inner.close();

  @override
  Datagram? receive() => _inner.receive();

  @override
  int send(List<int> buffer, InternetAddress address, int port) =>
      _inner.send(buffer, address, port);

  @override
  void joinMulticast(InternetAddress group, [NetworkInterface? interface]) {
    try {
      _inner.joinMulticast(group, interface);
    } catch (_) {
      // Ignored: On Windows, some network interfaces (e.g. Wi-Fi Direct virtual adapters)
      // throw SocketException (WSAENOPROTOOPT 10042) when joining multicast groups.
    }
  }

  @override
  void leaveMulticast(InternetAddress group, [NetworkInterface? interface]) {
    try {
      _inner.leaveMulticast(group, interface);
    } catch (_) {}
  }

  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);
}

