/// Represents an alternate audio track of the current media (multiple
/// languages, audio description, commentary) — the audio counterpart of
/// [NativeVideoPlayerSubtitleTrack]. Requested in issues #23 and #16.
class NativeVideoPlayerAudioTrack {
  const NativeVideoPlayerAudioTrack({
    required this.index,
    required this.language,
    required this.displayName,
    this.isSelected = false,
    this.codec,
    this.channelCount,
    this.bitrate,
  });

  factory NativeVideoPlayerAudioTrack.fromMap(Map<dynamic, dynamic> map) {
    return NativeVideoPlayerAudioTrack(
      index: map['index'] as int,
      language: map['language'] as String,
      displayName: map['displayName'] as String,
      isSelected: map['isSelected'] as bool? ?? false,
      // §engineVendor patch 11 — optionnels : une plateforme (ou une version
      // du natif) qui ne les envoie pas laisse simplement `null`.
      codec: map['codec'] as String?,
      channelCount: map['channelCount'] as int?,
      bitrate: map['bitrate'] as int?,
    );
  }

  /// Track index within the platform's audio track enumeration.
  final int index;

  /// Language code (e.g. "en", "nl", "en-US").
  final String language;

  /// Human-readable name (e.g. "English", "English (audio description)").
  final String displayName;

  /// Whether this track is currently playing.
  final bool isSelected;

  /// §engineVendor patch 11 — Sample MIME type of the track
  /// (`audio/ac3`, `audio/mp4a-latm`, `audio/vnd.dts`…), `null` when the
  /// platform doesn't report it. Lets an app know what a remote receiver
  /// would have to decode before it sends the stream there.
  final String? codec;

  /// Channel count (2 = stereo, 6 = 5.1), `null` when unknown.
  final int? channelCount;

  /// Average bitrate in bits per second, `null` when unknown.
  final int? bitrate;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'index': index,
    'language': language,
    'displayName': displayName,
    'isSelected': isSelected,
    if (codec != null) 'codec': codec,
    if (channelCount != null) 'channelCount': channelCount,
    if (bitrate != null) 'bitrate': bitrate,
  };

  @override
  String toString() =>
      'NativeVideoPlayerAudioTrack(index: $index, language: $language, '
      'displayName: $displayName, isSelected: $isSelected, codec: $codec, '
      'channelCount: $channelCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeVideoPlayerAudioTrack &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          language == other.language &&
          displayName == other.displayName &&
          isSelected == other.isSelected &&
          codec == other.codec &&
          channelCount == other.channelCount &&
          bitrate == other.bitrate;

  @override
  int get hashCode => Object.hash(
    index,
    language,
    displayName,
    isSelected,
    codec,
    channelCount,
    bitrate,
  );
}
