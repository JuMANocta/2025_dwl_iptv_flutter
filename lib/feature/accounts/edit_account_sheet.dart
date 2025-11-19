import 'package:flutter/material.dart';
import '../../data/models/stream_account.dart';

class EditAccountSheet extends StatefulWidget {
  final StreamAccount? initial;
  const EditAccountSheet({super.key, this.initial});

  @override
  State<EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends State<EditAccountSheet> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _label;
  late TextEditingController _completeUrl;
  late TextEditingController _baseUrl;
  late TextEditingController _username;
  late TextEditingController _password;
  late PlaylistType _playlistType;
  late TextEditingController _cookies;
  StreamAuthMode _mode = StreamAuthMode.completeUrl;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _label = TextEditingController(text: i?.label ?? "Compte");
    _completeUrl = TextEditingController(text: i?.completeUrl ?? "");
    _baseUrl = TextEditingController(text: i?.baseUrl ?? "");
    _username = TextEditingController(text: i?.username ?? "");
    _password = TextEditingController(text: i?.password ?? "");
    _playlistType = i?.playlistType ?? PlaylistType.m3u;
    _cookies = TextEditingController(text: i?.cookies ?? "");
    _mode = i?.mode ?? StreamAuthMode.completeUrl;
  }

  @override
  void dispose() {
    _label.dispose(); _completeUrl.dispose(); _baseUrl.dispose();
    _username.dispose(); _password.dispose(); _cookies.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final id = widget.initial?.id ?? "acc_${DateTime.now().millisecondsSinceEpoch}";
    final acc = StreamAccount(
      id: id,
      label: _label.text.trim().isEmpty ? "Compte source" : _label.text.trim(),
      mode: _mode,
      completeUrl: _mode == StreamAuthMode.completeUrl ? _completeUrl.text.trim() : null,
      baseUrl: _mode == StreamAuthMode.separate ? _baseUrl.text.trim() : null,
      username: _mode == StreamAuthMode.separate ? _username.text.trim() : null,
      password: _mode == StreamAuthMode.separate ? _password.text.trim() : null,
      playlistType: _playlistType,
      cookies: _cookies.text.trim().isEmpty ? null : _cookies.text.trim(),
    );
    Navigator.of(context).pop(acc);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                TextFormField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: "Nom du compte",
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                SegmentedButton<StreamAuthMode>(
                  segments: const [
                    ButtonSegment(
                      value: StreamAuthMode.completeUrl,
                      icon: Icon(Icons.link),
                      label: Text("URL complète"),
                    ),
                    ButtonSegment(
                      value: StreamAuthMode.separate,
                      icon: Icon(Icons.vpn_key_outlined),
                      label: Text("Séparé"),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s)=>setState(()=>_mode = s.first),
                ),
                const SizedBox(height: 12),
                if (_mode == StreamAuthMode.completeUrl) ...[
                  TextFormField(
                    controller: _completeUrl,
                    decoration: const InputDecoration(labelText: "URL .m3u complète"),
                    validator: (v)=> (v==null || v.trim().isEmpty) ? "Requis" : null,
                  ),
                ] else ...[
                  TextFormField(
                    controller: _baseUrl,
                    decoration: const InputDecoration(labelText: "Base URL (ex: https://host:port/)"),
                    validator: (v)=> (v==null || v.trim().isEmpty) ? "Requis" : null,
                  ),
                  Row(
                    children: [
                      Expanded(child: TextFormField(
                        controller: _username,
                        decoration: const InputDecoration(labelText: "Username"),
                        validator: (v)=> (v==null || v.trim().isEmpty) ? "Requis" : null,
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(labelText: "Password"),
                        validator: (v)=> (v==null || v.trim().isEmpty) ? "Requis" : null,
                      )),
                      const SizedBox(height: 16),
                    ],
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<PlaylistType>(
                    initialValue: _playlistType,
                    decoration: const InputDecoration(
                      labelText: 'Type de playlist',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.list_alt),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PlaylistType.m3u,
                        child: Text('m3u'),
                      ),
                      DropdownMenuItem(
                        value: PlaylistType.simple,
                        child: Text('Simple'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _playlistType = value;
                        });
                      }
                    },
                  ),
                ],

                const SizedBox(height: 24),
                FilledButton(onPressed: _save, child: const Text("Enregistrer")),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
