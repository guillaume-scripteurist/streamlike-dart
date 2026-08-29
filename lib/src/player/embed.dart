/// Construction de l'URL du player Streamlike.
///
/// Le player est une page hébergée qu'on met dans une iframe (web) ou dans une
/// WebView (natif). Il gère le streaming adaptatif, les sous-titres, les
/// chapitres, l'accessibilité, la reprise **et le comptage des lectures** — ce
/// dernier point étant ce qui fait toute la différence avec un player natif,
/// qui ne rapporte rien tant qu'on ne le lui fait pas faire à la main.
library;

import '../webservices/client.dart' show streamlikeCdn;

/// Média visé.
///
/// `permalink` est préférable dans une URL que quelqu'un peut voir : il se lit,
/// et il survit à une réimportation du média là où l'identifiant change.
class SlPlayerTarget {
  const SlPlayerTarget.permalink(String value)
      : permalink = value,
        mediaId = null,
        liveId = null,
        streamoutId = null;

  /// Par identifiant. Le player nomme ce paramètre `med_id` — même valeur que
  /// le `media_id` des webservices, nom différent pour raisons historiques.
  const SlPlayerTarget.media(String value)
      : mediaId = value,
        permalink = null,
        liveId = null,
        streamoutId = null;

  /// Canal en direct.
  const SlPlayerTarget.live(String value)
      : liveId = value,
        permalink = null,
        mediaId = null,
        streamoutId = null;

  /// Diffusion programmée (playlist jouée sur une grille horaire).
  const SlPlayerTarget.streamout(String value)
      : streamoutId = value,
        permalink = null,
        mediaId = null,
        liveId = null;

  final String? permalink;
  final String? mediaId;
  final String? liveId;
  final String? streamoutId;
}

/// Réglages du player.
///
/// Le player en accepte environ soixante-dix. Ceux qui portent un nom ici sont
/// ceux dont un réglage erroné ne se voit pas tout de suite ; les autres passent
/// par [extra], sans traduction, pour ne pas figer une liste qui bouge à chaque
/// version de la plateforme.
class SlPlayerOptions {
  const SlPlayerOptions({
    this.events = false,
    this.controls = true,
    this.playButton = true,
    this.autostart = false,
    this.muted,
    this.pid,
    this.userToken,
    this.token,
    this.startAt,
    this.subtitle,
    this.audioLanguage,
    this.fillBrowser = false,
    this.maxHeight,
    this.maxWidth,
    this.activeColor,
    this.tv = false,
    this.extra = const {},
    this.baseUrl,
  });

  /// Remonter les événements de lecture (`events=1`).
  ///
  /// Indispensable pour piloter le player depuis la page et pour savoir qu'une
  /// vidéo est terminée. Sans lui, un fil qui enchaîne s'arrête à la première.
  final bool events;
  final bool controls;
  final bool playButton;

  /// Démarrer seul.
  ///
  /// **Les navigateurs refusent une lecture automatique avec le son.**
  /// `autostart` sans [muted] laisse la vidéo sur sa première image, sans
  /// erreur et sans message : c'est la panne la plus fréquente de tout ce
  /// fichier. La paire qui marche est `autostart: true, muted: true`, avec une
  /// porte « activer le son » côté application.
  final bool autostart;
  final bool? muted;

  /// **Configuration de player** enregistrée dans le back-office : couleurs,
  /// logo, contrôles. La régler là-bas plutôt que dans l'URL permet de la
  /// changer sans republier l'application — ce qui, sur un téléphone, est la
  /// différence entre « demain » et « à la prochaine version du store ».
  final String? pid;

  /// Identifiant de spectateur, jusqu'à 64 caractères, **choisi par nous**.
  ///
  /// Il transforme des compteurs anonymes en chiffres par personne : reprise de
  /// lecture, engagement individuel. Il désigne quelqu'un — un identifiant de
  /// compte interne ou une valeur aléatoire par compte, jamais une adresse
  /// e-mail ni rien de lisible, et à documenter dans la politique de
  /// confidentialité.
  final String? userToken;

  /// Jeton de lecture d'un média protégé (`sltoken`), signé par le serveur.
  ///
  /// Émis par demande de lecture, après notre propre contrôle d'autorisation.
  /// Jamais fabriqué sur l'appareil : cela supposerait une clé d'API dans
  /// l'application.
  final String? token;

  /// Position de départ.
  final Duration? startAt;

  /// Force la langue des sous-titres (`fr`), ou `''` pour les couper.
  final String? subtitle;

  /// Force la piste audio (`en`) ; le suffixe `-ad` vise l'audiodescription.
  final String? audioLanguage;

  /// Remplit la zone quitte à rogner l'image, plutôt que de la déformer.
  final bool fillBrowser;

  /// Plafonne les qualités proposées. En données mobiles, c'est ce qui évite
  /// qu'un téléphone tire une échelle 1080p pour un player grand comme une carte.
  final int? maxHeight;
  final int? maxWidth;

  /// Couleur des éléments actifs, hexadécimal — le `#` est retiré s'il est là.
  final String? activeColor;

  /// Retire contrôles et bouton de lecture et force la lecture — mode affichage.
  final bool tv;

  /// Tout autre paramètre du player, tel quel. Les booléens deviennent `1`/`0`.
  final Map<String, Object?> extra;

  final String? baseUrl;

  SlPlayerOptions copyWith({
    bool? events,
    bool? controls,
    bool? playButton,
    bool? autostart,
    bool? muted,
    String? pid,
    String? userToken,
    String? token,
    Duration? startAt,
    String? subtitle,
    String? audioLanguage,
    bool? fillBrowser,
    int? maxHeight,
    int? maxWidth,
    String? activeColor,
    bool? tv,
    Map<String, Object?>? extra,
    String? baseUrl,
  }) {
    return SlPlayerOptions(
      events: events ?? this.events,
      controls: controls ?? this.controls,
      playButton: playButton ?? this.playButton,
      autostart: autostart ?? this.autostart,
      muted: muted ?? this.muted,
      pid: pid ?? this.pid,
      userToken: userToken ?? this.userToken,
      token: token ?? this.token,
      startAt: startAt ?? this.startAt,
      subtitle: subtitle ?? this.subtitle,
      audioLanguage: audioLanguage ?? this.audioLanguage,
      fillBrowser: fillBrowser ?? this.fillBrowser,
      maxHeight: maxHeight ?? this.maxHeight,
      maxWidth: maxWidth ?? this.maxWidth,
      activeColor: activeColor ?? this.activeColor,
      tv: tv ?? this.tv,
      extra: extra ?? this.extra,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }

  /// Diffusion sur un écran sans personne devant : démarre seul et **muet**.
  static const SlPlayerOptions broadcast = SlPlayerOptions(
    events: true,
    controls: false,
    playButton: false,
    autostart: true,
    muted: true,
  );

  /// Prévisualisation : la personne pilote, on ne démarre pas dans son dos.
  static const SlPlayerOptions preview = SlPlayerOptions(
    events: true,
    controls: true,
    playButton: true,
    autostart: false,
  );

  /// Carte d'un fil vertical sur téléphone : remplit, démarre muet, plafonne
  /// la qualité pour ne pas vider le forfait de données.
  static const SlPlayerOptions feed = SlPlayerOptions(
    events: true,
    controls: false,
    playButton: false,
    autostart: true,
    muted: true,
    fillBrowser: true,
    maxHeight: 720,
  );

  /// Relecture de sa propre vidéo dans une application : contrôles visibles,
  /// on attend un geste.
  static const SlPlayerOptions review = SlPlayerOptions(
    events: true,
    controls: true,
    playButton: true,
    autostart: false,
    maxHeight: 1080,
  );
}

/// URL du player pour une cible et des réglages donnés.
Uri buildPlayerUri(SlPlayerTarget target, [SlPlayerOptions options = const SlPlayerOptions()]) {
  final base = (options.baseUrl ?? streamlikeCdn).replaceAll(RegExp(r'/+$'), '');
  final params = <String, String>{};

  if (target.permalink != null) {
    params['permalink'] = target.permalink!;
  } else if (target.mediaId != null) {
    params['med_id'] = target.mediaId!;
  } else if (target.liveId != null) {
    params['live_id'] = target.liveId!;
  } else if (target.streamoutId != null) {
    params['str_id'] = target.streamoutId!;
  }

  // Le player lit `1`/`0`. Un booléen Dart sérialisé donnerait « false », une
  // chaîne non vide — donc « oui » pour le player.
  String flag(bool value) => value ? '1' : '0';

  params['events'] = flag(options.events);
  params['controls'] = flag(options.controls);
  params['play_button'] = flag(options.playButton);
  params['autostart'] = flag(options.autostart);
  if (options.muted != null) params['muted'] = flag(options.muted!);
  if (options.pid != null && options.pid!.isNotEmpty) params['pid'] = options.pid!;
  if (options.userToken != null && options.userToken!.isNotEmpty) {
    // La plateforme plafonne à 64 caractères ; au-delà elle tronque en silence,
    // et deux spectateurs dont les identifiants ne diffèrent qu'après le 64e
    // caractère deviendraient la même personne dans les statistiques.
    final token = options.userToken!;
    params['user_token'] = token.length > 64 ? token.substring(0, 64) : token;
  }
  if (options.token != null && options.token!.isNotEmpty) params['sltoken'] = options.token!;
  if (options.startAt != null && options.startAt!.inSeconds > 0) {
    params['streamlike_mp_starttc'] = '${options.startAt!.inSeconds}';
  }
  if (options.subtitle != null) {
    params['subtitle'] = options.subtitle!.isEmpty ? '0' : options.subtitle!;
  }
  if (options.audioLanguage != null && options.audioLanguage!.isNotEmpty) {
    params['audio_lng'] = options.audioLanguage!;
  }
  if (options.fillBrowser) params['fill_browser'] = '1';
  if (options.maxHeight != null) params['max_height'] = '${options.maxHeight}';
  if (options.maxWidth != null) params['max_width'] = '${options.maxWidth}';
  if (options.activeColor != null && options.activeColor!.isNotEmpty) {
    // Sans `#` : le `#` couperait l'URL au fragment, et tout ce qui suit la
    // couleur disparaîtrait sans le moindre message.
    params['active_color'] = options.activeColor!.replaceFirst(RegExp(r'^#'), '');
  }
  if (options.tv) params['tv'] = '1';

  options.extra.forEach((key, value) {
    if (value == null) return;
    params[key] = value is bool ? flag(value) : value.toString();
  });

  return Uri.parse('$base/play').replace(queryParameters: params);
}

/// Raccourci : l'URL du player pour un média, en chaîne.
String buildPlayerUrl(SlPlayerTarget target, [SlPlayerOptions options = const SlPlayerOptions()]) =>
    buildPlayerUri(target, options).toString();
