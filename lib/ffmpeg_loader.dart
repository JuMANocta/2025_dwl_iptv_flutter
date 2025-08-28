import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';

class FFmpegLoader {
  static Future<String> prepareFFmpeg(BuildContext context) async {
    try {
      final arch = await _detectArch();
      final assetName = 'assets/ffmpeg/ffmpeg_$arch';
      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/ffmpeg';
      final outFile = File(outPath);

      // Vérifie si le fichier existe déjà et est exécutable
      if (await outFile.exists()) {
        final result = await Process.run('ls', ['-l', outPath]);
        if (result.stdout.toString().contains('x')) {
          _showToast(context, '✅ FFmpeg déjà prêt.');
          print('✅ FFmpeg est déjà prêt à l\'emploi à $outPath');
          return outPath;
        }
      }

      _showToast(context, '📦 Extraction de FFmpeg...');
      print('📦 Début de l\'extraction de FFmpeg depuis $assetName');

      // Charge le binaire depuis les assets
      final byteData = await rootBundle.load(assetName);
      await outFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      // Rends le fichier exécutable
      await Process.run('chmod', ['+x', outPath]);

      _showToast(context, '✅ FFmpeg prêt à l\'emploi.');
      print('✅ FFmpeg est prêt et situé à $outPath');
      return outPath;
    } catch (e) {
      _showToast(context, '❌ Erreur lors de l\'installation de FFmpeg');
      print('❌ Erreur lors de la préparation de FFmpeg : $e');
      rethrow;
    }
  }

  static Future<String> _detectArch() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final cpuAbi = androidInfo.supportedAbis.first;
    print('🔍 ABI détectée : $cpuAbi');

    if (cpuAbi.contains('arm64')) return 'arm64';
    if (cpuAbi.contains('armeabi')) return 'armeabi';
    if (cpuAbi.contains('x86_64')) return 'x86_64';

    throw UnsupportedError('Architecture non supportée : $cpuAbi');
  }

  static void _showToast(BuildContext context, String message) {
    if (context.mounted) {
      final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
      if (scaffoldMessenger != null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(message), duration: Duration(seconds: 2)),
        );
      }
    }
  }
}