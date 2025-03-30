import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';

class FFmpegLoader {
  static Future<String> prepareFFmpeg() async {
    final arch = await _detectArch();
    final assetName = 'assets/ffmpeg/ffmpeg_$arch';
    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/ffmpeg';
    final outFile = File(outPath);

    // Vérifie si le fichier existe déjà et est exécutable
    if (await outFile.exists()) {
      final result = await Process.run('ls', ['-l', outPath]);
      if (result.stdout.toString().contains('x')) {
        return outPath;
      }
    }

    // Charge le binaire depuis les assets
    final byteData = await rootBundle.load(assetName);
    await outFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

    // Rends le fichier exécutable
    await Process.run('chmod', ['+x', outPath]);

    return outPath;
  }

  static Future<String> _detectArch() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final cpuAbi = androidInfo.supportedAbis.first;

    if (cpuAbi.contains('arm64')) return 'arm64';
    if (cpuAbi.contains('armeabi')) return 'armeabi';
    if (cpuAbi.contains('x86_64')) return 'x86_64';

    throw UnsupportedError('Architecture non supportée : $cpuAbi');
  }
}