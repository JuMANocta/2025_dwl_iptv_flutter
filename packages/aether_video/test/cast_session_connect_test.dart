import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:better_native_video_player/cast.dart';
import 'package:flutter_test/flutter_test.dart';

/// §engineVendor patch 16 (AetherStream, revue 2026-09-11, D2B-06) — un
/// LAUNCH resté sans réponse doit FERMER la session.
///
/// Amont, `CastSession.connect` sortait en `TimeoutException` sans rien
/// fermer : l'appelant ne recevant jamais la session, le socket TLS restait
/// ouvert et un PING partait toutes les 5 s pour la vie du processus. Ici, un
/// serveur TLS local accepte la connexion et ne répond JAMAIS (Chromecast en
/// veille) : après l'exception, le serveur doit voir la connexion se fermer.
///
/// Certificat auto-signé de test (CN=localhost, sans valeur : le client Cast
/// accepte tout certificat par construction, comme les vrais récepteurs).
const String _testCert = '''
-----BEGIN CERTIFICATE-----
MIIDCzCCAfOgAwIBAgIUSK5asHynf0UYg2XEVJdp4OgY9QMwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MDkxMTEyMTYyOFoYDzIxMjYw
ODE4MTIxNjI4WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwggEiMA0GCSqGSIb3DQEB
AQUAA4IBDwAwggEKAoIBAQC2CZOPYhEG3Y5/KetSTbBpLNOWf99qukfbapafa9iA
7v2hAAlVTYz/gdjCDG8bLYfpP7ky/4Ske0YSqdngQeH+vBnofSwqHRVBylAhb6EM
DzK566CXxzQjv8jWp38IoC7idME9US+dPrpiB32mlxsGg1XPNSTo+15xCq6z79yH
c+VGoFXVVaoWviHCgnQd5WBpgIa2gCZ4oaRYeT5sdYU3+UD+E+LQtwJbF3ugksT9
9spG0zgmq4CwPJXAPIjnAtWN6sTZ9KzWQs3KwnCLbV8Mz0gBTyfwQbSjhQw5e4HA
r+mqvQMuGUTqVEHfTVPm9O4/VU6NY/NKnMJJMXJer5irAgMBAAGjUzBRMB0GA1Ud
DgQWBBQEg9ZQgAFO6rm7pCgVqKTsSAz/3zAfBgNVHSMEGDAWgBQEg9ZQgAFO6rm7
pCgVqKTsSAz/3zAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQBo
q0D3y2EyJi3Qn+Yrgwcp3ZmAyWIzEgkOoxo9DzviPebjcEocpklGbsTI3ouXXUfb
DyOst0/krGmVz+0qdhsdxrNgNHX5hC8PzquArWDe6UYhsRZDYY6j7c/42Tu8wzRl
Wx0mV/jUlr2yhKZ61BSDqwcUDaEhKVr/vJtuxNLJiyjJ7IPtbV6M2E6PLH0xIyNv
QkCaz76en7VhhCZBZm2x8kJKm76lrU5kFYLSqOe5er5kZ93xNuucYTFni52L54tz
/lQrJTKOwpzdckLfnS0GhVAmk1zP5xiHNRR9ljlY+iAqBXkrhd30I9B025B1O50u
9dnZHJn18IVkvRScBy6c
-----END CERTIFICATE-----
''';

const String _testKey = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC2CZOPYhEG3Y5/
KetSTbBpLNOWf99qukfbapafa9iA7v2hAAlVTYz/gdjCDG8bLYfpP7ky/4Ske0YS
qdngQeH+vBnofSwqHRVBylAhb6EMDzK566CXxzQjv8jWp38IoC7idME9US+dPrpi
B32mlxsGg1XPNSTo+15xCq6z79yHc+VGoFXVVaoWviHCgnQd5WBpgIa2gCZ4oaRY
eT5sdYU3+UD+E+LQtwJbF3ugksT99spG0zgmq4CwPJXAPIjnAtWN6sTZ9KzWQs3K
wnCLbV8Mz0gBTyfwQbSjhQw5e4HAr+mqvQMuGUTqVEHfTVPm9O4/VU6NY/NKnMJJ
MXJer5irAgMBAAECggEACqQeqxgJdMRIyygxKFuAP3WuXLLW5Y9EGhBuA52zRz4x
N1MgOItS/bCich119TnBIyJlehSztUW7f+XL5a8UPebTAOMoTMHsdy8TZhD3chQF
XBbpCVZMtvZEEEA0TdXHR9eZYDM5vFBpZseXUcCthMDyqC0sHi5rg+Ii+kPAOW60
j2zAnLLIDW8n6r/qAhUygEGJA3ETm1TpNX6MmuQdraekRKGt0GYezyKZHyWYTAnP
1vuP4bcV1N4VNBpheG2fF00lb0XFgIe3i1h6GxRZnqDCI8CCY6P5bv9qrgrH+m/X
e/NnWyCbQT2fVwUyEwy1GaR2W8WpskwUr+Mg66INyQKBgQDuyeVJ6WL+/qcJtV2i
cS2S1rDjdjxhhcus9W+vMl7LUnU4n0eOmJecEa9Kfls0CTCdFjRtQOWcE25qr7Ds
dh71FWqgMBBRBdHVYWm05VFKzCrvJmMeh33Afk685Bg7F0ppCulOgGRPFRV4JD7n
dTnZWJIC1EO8C41c1BX1881szwKBgQDDKIMuCcqoaCFtl2mYrLRKCPPFZjbeg72s
YlGFghN7B/mlllTz6/LQhMkipmmWU5bOlPZF968R2uPQcJkjTZnvgteh7eeDsARx
widA7JPp0jmDHsVnSTNX2PoOjRZtic0VdCHNO+jKJAnCIv9hzY+Auxb1Xy4miw2X
2Cbb22plZQKBgCDSP2HZYnIKLot3ElexlsIIIGgjaEk/Sq+LTL6X/c+UlegifINt
FemtxJpIo+CTIst0seASe3zobtTbMUZPNhIZz34VHSkF08Gwkgb7PiE5zuzwKc+Y
cAB1W/06nNoCaYfmqArSOvdjvn+0+7B0vG7Tbb5VzrmaHOQVgq87w5ChAoGBAIBo
Oo/jL23JPh1un7MuB14jL8n1bCrSgc1Xz43JvWmZIMC7/l+UIuriQ7lBx316uGJq
jvQQeSeFX5n5TDl3SM7Xx2urLkZuXS5AcjV8tAIIKYFFkNtZxaeKg1VprZUbM05n
YAo63fuK5MTQ5DoE1+P6tatzGdmQarw7I65LW2ElAoGAEeKZPhzVuWEtc8ocQ4vd
xOvONE9NZ0r4MbdTvzlA/baAsM4KoJI15eSdB3K+09/18hLRyFMkx3Olivx/Tz+O
BeeXAPrSeRYE76kY1nn4kwpVWneVGi+mKPzrJyvga1eiUBcabyAGweXRNCbkrSBt
xyTg/fdm8bMAHME77h3duVc=
-----END PRIVATE KEY-----
''';

void main() {
  test(
    'LAUNCH sans réponse : TimeoutException ET connexion fermée côté serveur',
    () async {
      final context = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(_testCert))
        ..usePrivateKeyBytes(utf8.encode(_testKey));
      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(server.close);

      final closed = Completer<void>();
      var bytesReceived = 0;
      server.listen((socket) {
        // Un récepteur « en veille » : il lit, ne répond jamais.
        socket.listen(
          (chunk) => bytesReceived += chunk.length,
          onDone: () {
            if (!closed.isCompleted) closed.complete();
            socket.destroy();
          },
          onError: (Object _) {
            if (!closed.isCompleted) closed.complete();
          },
        );
      });

      final device = CastDevice(
        id: 'muet',
        name: 'muet',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );

      await expectLater(
        CastSession.connect(device, timeout: const Duration(milliseconds: 500)),
        throwsA(isA<TimeoutException>()),
      );

      // Sans le patch 16, la connexion resterait ouverte (et un PING
      // partirait toutes les 5 s) : ce futur ne se terminerait jamais.
      await closed.future.timeout(const Duration(seconds: 5));
      // CONNECT + LAUNCH sont bien partis avant l'abandon.
      expect(bytesReceived, greaterThan(0));
    },
  );
}
