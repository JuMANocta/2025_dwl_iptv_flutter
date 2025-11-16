import 'package:flutter/material.dart';
import 'services/playlist_service.dart';
import 'services/stream_account_service.dart';

/// Écran de compatibilité pour télécharger la playlist .m3u
/// Désormais, on passe par PlaylistService.downloadCurrentM3U()
class TelechargementPage extends StatefulWidget {
  const TelechargementPage({super.key});

  @override
  State<TelechargementPage> createState() => _TelechargementPageState();
}

class _TelechargementPageState extends State<TelechargementPage> {
  bool _loading = false;
  String? _lastPath;

  Future<void> _download() async {
    setState(() {
      _loading = true;
      _lastPath = null;
    });

    try {
      final path = await PlaylistService.downloadCurrentM3U();
      setState(() => _lastPath = path);

      final acc = await StreamAccountService.getCurrentAccount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Playlist téléchargée pour « ${acc?.label ?? "Compte"} »."))
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Échec du téléchargement : $e"))
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _loading = true);
    try {
      await PlaylistService.deleteExisting();
      if (!mounted) return;
      setState(() => _lastPath = null);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("🗑️ Playlist supprimée."))
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Impossible de supprimer : $e"))
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = _loading
        ? const SizedBox(
      height: 20, width: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    )
        : const Icon(Icons.download);

    return Scaffold(
      appBar: AppBar(title: const Text("Téléchargement de la playlist")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.list_alt),
                title: const Text("Playlist .m3u"),
                subtitle: Text(
                  _lastPath == null
                      ? "Aucune playlist téléchargée dans ce contexte."
                      : "Dernier fichier : $_lastPath",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _download,
                    icon: action,
                    label: const Text("Télécharger / Mettre à jour"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _delete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text("Supprimer"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              "Astuce : tu peux aussi recharger la playlist depuis la roue crantée "
                  "ou via l'icône de rafraîchissement sur l'écran de recherche.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
