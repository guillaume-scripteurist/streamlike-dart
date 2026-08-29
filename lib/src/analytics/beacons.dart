/// Audience : ce qu'il faut émettre quand on ne joue **pas** avec le player
/// Streamlike.
///
/// Le player de la plateforme rapporte tout seul. Un player natif — `video_player`
/// en Flutter, ExoPlayer, AVPlayer — ne rapporte **rien**. C'est la première
/// cause de « la console dit que personne ne regarde nos vidéos » : le trafic
/// apparaît bien dans la consommation, les lectures nulle part. L'écart est
/// d'ailleurs aussi la façon dont la plateforme repère un vol de bande passante.
///
/// Deux balises, deux mesures différentes — ne pas les confondre :
///   - `o.k`   : **une** lecture. Une seule fois, au premier « ça joue ».
///   - `eng.k` : les **segments** réellement vus. Régulièrement, et à chaque
///               saut, parce qu'un saut termine un segment et en ouvre un autre.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../webservices/client.dart' show streamlikeCdn;

/// Type de flux joué, tel que la plateforme le nomme.
enum SlStreamType {
  hls('hls'),
  mp4('mp4'),
  mp3('mp3');

  const SlStreamType(this.value);
  final String value;
}

/// URL de comptage d'**une** lecture.
///
/// Chaque appel compte une vue. La tirer à la construction d'un widget, ou à
/// chaque événement « lecture » (qui se déclenche aussi après une pause),
/// gonfle les chiffres sans que rien ne le signale.
Uri playbackBeaconUri({
  required String mediaId,
  SlStreamType? streamType,
  String? playerName,
  int? timestamp,
  String baseUrl = streamlikeCdn,
}) {
  return Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/o.k').replace(
    queryParameters: {
      'm': mediaId,
      // Anti-cache : sans lui, un proxy peut servir la même réponse et la
      // lecture n'est jamais comptée.
      't': '${timestamp ?? DateTime.now().millisecondsSinceEpoch}',
      if (streamType != null) 's': streamType.value,
      if (playerName != null) 'p': playerName,
    },
  );
}

/// URL de report d'un **segment** vu.
///
/// Les segments qui se chevauchent sont normaux et attendus : c'est ce qui rend
/// les replays visibles, et pourquoi l'engagement peut dépasser 1.
Uri engagementBeaconUri({
  required String mediaId,
  required Duration duration,
  required SlStreamType streamType,
  required int qualityHeight,
  required String playerName,
  required Duration from,
  required Duration to,
  String? sessionId,
  String? userToken,
  String? fingerprint,
  int? timestamp,
  String baseUrl = streamlikeCdn,
}) {
  final total = duration.inMilliseconds / 1000;
  // Bornés à la durée : la plateforme rejette un segment qui en sort, et le
  // rejet d'un GET dont personne ne lit la réponse est totalement invisible.
  final start = (from.inMilliseconds / 1000).clamp(0.0, total);
  final end = (to.inMilliseconds / 1000).clamp(start, total);

  return Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/eng.k').replace(
    queryParameters: {
      'm': mediaId,
      'd': '${total.round()}',
      't': streamType.value,
      'q': '$qualityHeight',
      'p': playerName,
      'ts': '${timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'rs': _fmt(start),
      're': _fmt(end),
      if (sessionId != null) 's': sessionId,
      if (userToken != null) 'u': userToken,
      if (fingerprint != null) 'f': fingerprint,
    },
  );
}

String _fmt(double value) {
  final rounded = double.parse(value.toStringAsFixed(3));
  return rounded == rounded.roundToDouble() ? '${rounded.round()}' : '$rounded';
}

/// Un segment mérite-t-il d'être rapporté ?
///
/// Un segment nul ou négatif arrive à chaque retour en arrière et à chaque
/// pause immédiate. Le rapporter ajoute du bruit sans rien mesurer.
bool isReportableSegment(Duration from, Duration to) =>
    to.inMilliseconds - from.inMilliseconds >= 500;

/// Émetteur de balises pour un player natif.
///
/// Tient les deux règles qui se perdent toujours dans un widget :
/// **une** lecture comptée par lecture, et un segment fermé à chaque saut.
///
/// ```dart
/// final reporter = SlPlaybackReporter(
///   mediaId: media.id, duration: media.duration,
///   playerName: 'kiosk-mobile', userToken: session.userToken,
/// );
/// controller.addListener(() {
///   reporter.onPosition(controller.value.position, playing: controller.value.isPlaying);
/// });
/// // …au démontage :
/// await reporter.flush();
/// ```
class SlPlaybackReporter {
  SlPlaybackReporter({
    required this.mediaId,
    required this.duration,
    required this.playerName,
    this.streamType = SlStreamType.hls,
    this.qualityHeight = 720,
    this.userToken,
    this.sessionId,
    http.Client? httpClient,
    this.reportEvery = const Duration(seconds: 10),
    this.baseUrl = streamlikeCdn,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final String mediaId;
  final Duration duration;
  final String playerName;
  final SlStreamType streamType;
  final int qualityHeight;
  final String? userToken;
  final String? sessionId;
  final Duration reportEvery;
  final String baseUrl;

  final http.Client _http;
  final bool _ownsClient;

  bool _playbackCounted = false;
  Duration? _segmentStart;
  Duration _lastPosition = Duration.zero;

  /// À appeler à chaque changement de position du player.
  ///
  /// Détecte les sauts : un bond de plus de deux secondes par rapport à la
  /// position précédente ferme le segment courant et en ouvre un autre. Sans
  /// cela, sauter de la minute 1 à la minute 40 déclarerait 39 minutes vues.
  void onPosition(Duration position, {required bool playing}) {
    if (!playing) {
      _closeSegment(position);
      _lastPosition = position;
      return;
    }

    if (!_playbackCounted) {
      _playbackCounted = true;
      _fire(playbackBeaconUri(
        mediaId: mediaId,
        streamType: streamType,
        playerName: playerName,
        baseUrl: baseUrl,
      ));
    }

    final start = _segmentStart;
    if (start == null) {
      _segmentStart = position;
    } else {
      final jumped = (position - _lastPosition).abs() > const Duration(seconds: 2);
      if (jumped || position - start >= reportEvery) {
        _closeSegment(_lastPosition);
        _segmentStart = position;
      }
    }
    _lastPosition = position;
  }

  /// À appeler au démontage, ou quand la lecture s'arrête pour de bon.
  ///
  /// Le dernier segment est le plus souvent perdu si on ne le ferme pas : une
  /// application qu'on referme n'envoie plus rien.
  Future<void> flush() async {
    _closeSegment(_lastPosition);
    if (_ownsClient) _http.close();
  }

  void _closeSegment(Duration end) {
    final start = _segmentStart;
    _segmentStart = null;
    if (start == null || !isReportableSegment(start, end)) return;
    _fire(engagementBeaconUri(
      mediaId: mediaId,
      duration: duration,
      streamType: streamType,
      qualityHeight: qualityHeight,
      playerName: playerName,
      from: start,
      to: end,
      userToken: userToken,
      sessionId: sessionId,
      baseUrl: baseUrl,
    ));
  }

  /// Tire une balise sans attendre ni relancer.
  ///
  /// Une balise perdue coûte une ligne de statistique ; une balise qui bloque
  /// la lecture, ou qu'on rejoue en boucle sur un réseau instable, coûte la
  /// vidéo. On ignore donc l'échec, délibérément.
  void _fire(Uri uri) {
    unawaited(_http.get(uri).then<void>((_) {}, onError: (Object _) {}));
  }
}
