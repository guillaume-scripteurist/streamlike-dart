/// Le protocole `postMessage` du player, en Dart pur.
///
/// Le player, appelé avec `events=1`, **pousse** vers la page qui l'héberge :
///
/// ```
/// ["sl-progress", 24.363924]              ~4 fois par seconde
/// ["sl-state", "play" | "pause" | "ended"]
/// ```
///
/// et **reçoit** `["play"]`, `["pause"]`, `["seek", 30.4]`…
///
/// Ce fichier ne connaît ni `dart:html` ni `package:web` : il se contente de
/// fabriquer et de lire les charges utiles. Le transport est propre à la
/// plateforme d'exécution — `postMessage` sur une iframe en web, un canal de
/// WebView sur mobile — et c'est justement ce qui doit rester dehors pour que
/// ce paquet reste utilisable partout.
library;

import 'dart:convert';

/// État de lecture rapporté par le player.
enum SlPlayerState {
  play,
  pause,
  ended;

  static SlPlayerState? parse(Object? value) {
    switch (value?.toString()) {
      case 'play':
        return SlPlayerState.play;
      case 'pause':
        return SlPlayerState.pause;
      case 'ended':
        return SlPlayerState.ended;
      default:
        return null;
    }
  }
}

/// Un événement poussé par le player.
sealed class SlPlayerEvent {
  const SlPlayerEvent();
}

/// Changement d'état de lecture.
class SlStateEvent extends SlPlayerEvent {
  const SlStateEvent(this.state);
  final SlPlayerState state;
}

/// Position de lecture. Émis environ quatre fois par seconde.
class SlProgressEvent extends SlPlayerEvent {
  const SlProgressEvent(this.position);
  final Duration position;
  double get seconds => position.inMilliseconds / 1000;
}

/// Lit un message venu du player.
///
/// Rend `null` pour tout ce qui n'est pas du player : une page reçoit des
/// messages de bien d'autres sources (extensions, autres iframes), et les
/// traiter tous comme des événements de lecture ferait sauter des vidéos dans
/// une file. **Le filtrage sur la provenance reste indispensable** — celui-ci
/// ne fait que la forme.
SlPlayerEvent? parsePlayerMessage(Object? data) {
  Object? decoded = data;
  if (data is String) {
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return null;
    }
  }
  if (decoded is! List || decoded.isEmpty) return null;

  switch (decoded.first) {
    case 'sl-progress':
      final seconds = decoded.length > 1 ? decoded[1] : null;
      final value = seconds is num ? seconds.toDouble() : double.tryParse('$seconds') ?? 0;
      return SlProgressEvent(Duration(milliseconds: (value * 1000).round()));
    case 'sl-state':
      final state = SlPlayerState.parse(decoded.length > 1 ? decoded[1] : null);
      return state == null ? null : SlStateEvent(state);
    default:
      return null;
  }
}

/// Commandes que la page peut envoyer au player.
enum SlPlayerCommand {
  play('play'),
  pause('pause'),
  stop('stop'),

  /// Couper le son.
  ///
  /// Distinct d'un volume à zéro : un démarrage automatique n'est autorisé par
  /// le navigateur que sur un player **déclaré** muet. Baisser le volume ne
  /// suffit pas, la lecture est refusée quand même.
  mute('mute'),
  unmute('unmute'),

  /// Bascule le plein écran. Le navigateur ne l'accorde que sur un geste de
  /// l'utilisateur : appelée depuis un minuteur, la commande est ignorée.
  fullscreen('fullscreen');

  const SlPlayerCommand(this.value);
  final String value;
}

/// Sérialise une commande sans argument.
String encodePlayerCommand(SlPlayerCommand command) => jsonEncode([command.value]);

/// Sérialise un saut à une position.
String encodeSeek(Duration position) =>
    jsonEncode(['seek', position.inMilliseconds / 1000]);

/// Sérialise un changement de vitesse (1 = normal).
String encodeSpeed(double rate) => jsonEncode(['speed', rate]);

/// Sérialise un réglage de volume, borné à 0..1.
String encodeVolume(double level) =>
    jsonEncode(['volume', level.clamp(0.0, 1.0)]);
