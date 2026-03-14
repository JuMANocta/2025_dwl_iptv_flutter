import 'package:flutter/material.dart';
import '../../data/models/stream_account.dart';
import '../../l10n/app_localizations.dart';

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
  bool _isPasswordObscured = true;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _label = TextEditingController(text: i?.label ?? '');
    _completeUrl = TextEditingController(text: i?.completeUrl ?? '');
    _baseUrl = TextEditingController(text: i?.baseUrl ?? '');
    _username = TextEditingController(text: i?.username ?? '');
    _password = TextEditingController(text: i?.password ?? '');
    _playlistType = i?.playlistType ?? PlaylistType.m3u;
    _cookies = TextEditingController(text: i?.cookies ?? '');
    _mode = i?.mode ?? StreamAuthMode.completeUrl;
  }

  @override
  void dispose() {
    _label.dispose();
    _completeUrl.dispose();
    _baseUrl.dispose();
    _username.dispose();
    _password.dispose();
    _cookies.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    final id = widget.initial?.id ?? "acc_${DateTime.now().millisecondsSinceEpoch}";
    final acc = StreamAccount(
      id: id,
      label: _label.text.trim().isEmpty ? l10n.editAccountNameHint : _label.text.trim(),
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

  Widget _buildUrlModeFields(AppLocalizations l10n) {
    return TextFormField(
      controller: _completeUrl,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
          labelText: l10n.editAccountFullUrlLabel, prefixIcon: const Icon(Icons.public)),
      validator: (v) => (v == null || v.trim().isEmpty || !Uri.tryParse(v.trim())!.isAbsolute)
          ? l10n.editAccountFullUrlInvalid
          : null,
    );
  }

  Widget _buildSeparateModeFields(AppLocalizations l10n) {
    return Column(
      children: [
        TextFormField(
          controller: _baseUrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
              labelText: l10n.editAccountServerUrlLabel,
              prefixIcon: const Icon(Icons.dns)),
          validator: (v) => (v == null || v.trim().isEmpty || !Uri.tryParse(v.trim())!.isAbsolute)
              ? l10n.editAccountFullUrlInvalid
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _username,
          decoration: InputDecoration(
              labelText: l10n.editAccountUsernameLabel, prefixIcon: const Icon(Icons.person_outline)),
          validator: (v) =>
          (v == null || v.trim().isEmpty) ? l10n.editAccountNameRequired : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _password,
          obscureText: _isPasswordObscured,
          decoration: InputDecoration(
            labelText: l10n.editAccountPasswordLabel,
            prefixIcon: const Icon(Icons.password),
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordObscured ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() => _isPasswordObscured = !_isPasswordObscured);
              },
            ),
          ),
          validator: (v) =>
          (v == null || v.trim().isEmpty) ? l10n.editAccountNameRequired : null,
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<PlaylistType>(
          initialValue: _playlistType,
          decoration: InputDecoration(
            labelText: l10n.editAccountPlaylistTypeLabel,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.list_alt),
          ),
          items: [
            DropdownMenuItem(value: PlaylistType.m3u, child: Text(l10n.editAccountPlaylistTypeM3u)),
            DropdownMenuItem(value: PlaylistType.simple, child: Text(l10n.editAccountPlaylistTypeSimple)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _playlistType = value);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.initial == null ? l10n.editAccountTitleAdd : l10n.editAccountTitleEdit,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _label,
                  decoration: InputDecoration(
                    labelText: l10n.editAccountNameLabel,
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? l10n.editAccountNameRequired : null,
                ),
                const SizedBox(height: 24),
                SegmentedButton<StreamAuthMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: StreamAuthMode.completeUrl, icon: const Icon(Icons.link), label: Text(l10n.editAccountModeUrl)),
                    ButtonSegment(value: StreamAuthMode.separate, icon: const Icon(Icons.person_pin_circle_outlined), label: Text(l10n.editAccountModeCredentials)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: 24),
                if (_mode == StreamAuthMode.completeUrl)
                  _buildUrlModeFields(l10n)
                else
                  _buildSeparateModeFields(l10n),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _cookies,
                  decoration: InputDecoration(
                    labelText: l10n.editAccountCookiesLabel,
                    prefixIcon: const Icon(Icons.cookie_outlined),
                    hintText: l10n.editAccountCookiesHint,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: Text(l10n.editAccountSaveButton),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
