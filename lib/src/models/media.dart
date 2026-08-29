/// Modèles des webservices `/ws/*`.
///
/// Le JSON de Streamlike est profondément imbriqué et hétérogène : un média
/// arrive sous `{media: {metadata: {global: {…}}}}`, les listes sous
/// `[{media: {…}}]`, et **les blocs vides sont absents plutôt que vides** — un
/// média sans sous-titres n'a pas de clé `subtitles` du tout, alors qu'un média
/// sans description porte bien `description: ""`. En Dart, ce mélange se paie
/// comptant : un `as String` sur un champ absent lève, et le rendu s'arrête.
///
/// On normalise donc une fois, ici, et jamais dans les widgets.
library;

String _str(Object? v) => v == null ? '' : v.toString();

double _num(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse(_str(v)) ?? 0;
}

int _int(Object? v) => _num(v).round();

/// Booléen de la plateforme.
///
/// Les drapeaux arrivent tantôt en `true`, tantôt en `"1"`, tantôt en `1`.
/// `"0"` est une chaîne non vide : le prendre pour vrai masquerait tout le
/// catalogue derrière un message « média protégé ».
bool _bool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = _str(v).trim().toLowerCase();
  return s == '1' || s == 'true' || s == 'yes';
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

/// Déballe les listes `[{media: {…}}]` que Streamlike renvoie.
///
/// Chaque entrée est un objet à une seule clé qui répète le nom du type. La
/// forme nue est acceptée au cas où une version de la plateforme cesserait
/// d'envelopper.
List<dynamic> _unwrap(Object? raw, String key) {
  if (raw is! List) return const [];
  return raw
      .map((entry) => entry is Map && entry.containsKey(key) ? entry[key] : entry)
      .where((entry) => entry != null)
      .toList();
}

/// Jaquette d'un média, dans ses quatre tailles.
class SlCover {
  const SlCover({
    this.url = '',
    this.thumbnailUrl = '',
    this.thumbnailLargeUrl = '',
    this.thumbnailExtraLargeUrl = '',
  });

  final String url;
  final String thumbnailUrl;
  final String thumbnailLargeUrl;
  final String thumbnailExtraLargeUrl;

  /// La plus grande vignette disponible, en descendant jusqu'à la jaquette.
  ///
  /// Les quatre tailles ne sont pas toutes remplies selon les comptes ; un
  /// `Image.network('')` affiche une erreur, pas un vide.
  String get best {
    for (final candidate in [
      thumbnailExtraLargeUrl,
      thumbnailLargeUrl,
      thumbnailUrl,
      url,
    ]) {
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  factory SlCover.fromJson(Map<String, dynamic> json) => SlCover(
        url: _str(json['url']),
        thumbnailUrl: _str(json['thumbnail_url']),
        thumbnailLargeUrl: _str(json['thumbnaillarge_url']),
        thumbnailExtraLargeUrl: _str(json['thumbnailextralarge_url']),
      );
}

/// Une piste de sous-titres, dans ses quatre formats.
class SlSubtitle {
  const SlSubtitle({
    required this.language,
    this.vtt = '',
    this.srt = '',
    this.dfxp = '',
    this.m3u8 = '',
  });

  final String language;

  /// Format des navigateurs (`<track>`) — le seul qui serve côté web.
  final String vtt;
  final String srt;
  final String dfxp;

  /// Format HLS, pour un player natif.
  final String m3u8;

  factory SlSubtitle.fromJson(Map<String, dynamic> json) {
    final url = _map(json['url']);
    return SlSubtitle(
      language: _str(json['language_id']),
      vtt: _str(url['vtt']),
      srt: _str(url['srt']),
      dfxp: _str(url['dfxp']),
      m3u8: _str(url['m3u8']),
    );
  }
}

/// Rattachement d'un média à une playlist.
class SlMediaPlaylist {
  const SlMediaPlaylist({
    required this.id,
    required this.name,
    this.type = '',
    this.position = 0,
  });

  final String id;
  final String name;
  final String type;
  final int position;
}

/// Compteurs publics d'un média.
class SlStatistics {
  const SlStatistics({
    this.playbacks = 0,
    this.ratingHits = 0,
    this.ratingTotal = 0,
  });

  /// Nombre de lectures (`statistics.media_access`).
  final int playbacks;
  final int ratingHits;
  final double ratingTotal;

  /// Note moyenne, ou `null` quand personne n'a voté.
  ///
  /// `null` et non `0` : une moyenne de zéro se dessine comme « très mauvais »,
  /// alors qu'il n'y a simplement pas encore d'avis.
  double? get ratingAverage => ratingHits > 0 ? ratingTotal / ratingHits : null;

  factory SlStatistics.fromJson(Map<String, dynamic> json) => SlStatistics(
        playbacks: _int(json['media_access']),
        ratingHits: _int(json['rating_hits']),
        ratingTotal: _num(json['rating_totalvalue']),
      );
}

/// Un média, aplati depuis `/ws/media` ou `/ws/playlist`.
class SlMedia {
  const SlMedia({
    required this.id,
    required this.name,
    required this.permalink,
    this.type = 'video',
    this.status = '',
    this.description = '',
    this.transcript = '',
    this.credits = '',
    this.durationSec = 0,
    this.ratio = 0,
    this.fps = 0,
    this.createdAt = '',
    this.releasedAt = '',
    this.updatedAt = '',
    this.lastPlaybackAt = '',
    this.is360 = false,
    this.isMultipleAudio = false,
    this.isTokenized = false,
    this.hasPassword = false,
    this.isDownloadable = false,
    this.isSecured = false,
    this.universalUrl = '',
    this.cover = const SlCover(),
    this.mosaicUrl = '',
    this.subtitles = const [],
    this.languages = const [],
    this.playlists = const [],
    this.keywords = const [],
    this.statistics = const SlStatistics(),
    this.manifestUrl,
    this.raw = const {},
  });

  final String id;
  final String name;
  final String permalink;
  final String type;
  final String status;
  final String description;

  /// Transcription complète, quand la reconnaissance vocale a tourné.
  final String transcript;
  final String credits;

  /// Durée en **secondes**.
  final double durationSec;

  /// Rapport largeur/hauteur. Vaut 0 quand la plateforme ne l'a pas calculé —
  /// ne pas diviser sans vérifier ; voir `aspectRatio`.
  final double ratio;
  final double fps;
  final String createdAt;
  final String releasedAt;
  final String updatedAt;
  final String lastPlaybackAt;
  final bool is360;
  final bool isMultipleAudio;
  final bool isTokenized;
  final bool hasPassword;
  final bool isDownloadable;
  final bool isSecured;
  final String universalUrl;
  final SlCover cover;

  /// Storyboard (mosaïque de vignettes).
  final String mosaicUrl;
  final List<SlSubtitle> subtitles;
  final List<String> languages;
  final List<SlMediaPlaylist> playlists;
  final List<String> keywords;
  final SlStatistics statistics;

  /// Index JSON de tous les fichiers encodés.
  ///
  /// C'est la voie **sans liste blanche d'IP** vers le master HLS : le
  /// webservice `/ws/manifest` rend la même chose mais exige une IP autorisée.
  final String? manifestUrl;

  /// La réponse non normalisée, pour les champs que ce modèle ne couvre pas.
  final Map<String, dynamic> raw;

  /// Rapport d'image utilisable tel quel dans un `AspectRatio`.
  ///
  /// 16/9 par défaut : un rapport nul ferait une boîte de hauteur zéro, donc
  /// une vidéo invisible plutôt qu'une vidéo mal cadrée.
  double get aspectRatio => ratio > 0 ? ratio : 16 / 9;

  Duration get duration => Duration(milliseconds: (durationSec * 1000).round());

  factory SlMedia.fromJson(Map<String, dynamic> raw) {
    // `/ws/media` enveloppe dans `media`, `/ws/playlist` livre l'objet nu.
    final media = _map(raw['media'] ?? raw);
    final meta = _map(media['metadata']);
    final g = _map(meta['global']);
    final customization = _map(meta['customization']);

    final manifests = _unwrap(media['html5_sources'], 'html5_source')
        .map((s) => _str(_map(s)['manifest']))
        .where((u) => u.isNotEmpty);

    return SlMedia(
      id: _str(g['media_id']),
      name: _str(g['name']),
      permalink: _str(g['permalink']),
      type: _str(g['type']).isEmpty ? 'video' : _str(g['type']),
      status: _str(g['status']),
      description: _str(g['description']),
      transcript: _str(g['transcript']),
      credits: _str(g['credits']),
      durationSec: _num(g['duration']),
      ratio: _num(g['ratio']),
      fps: _num(g['fps']),
      createdAt: _str(g['creation_date']),
      releasedAt: _str(g['release_date']),
      updatedAt: _str(g['lastupdated_date']),
      lastPlaybackAt: _str(g['lastplayback_date']),
      is360: _bool(g['is_360']),
      isMultipleAudio: _bool(g['is_multiple_audio']),
      isTokenized: _bool(g['is_tokenized']),
      hasPassword: _bool(g['has_password']),
      isDownloadable: _bool(g['is_downloadable']),
      isSecured: _bool(g['is_secured']),
      universalUrl: _str(_map(meta['share'])['universal_url']),
      cover: SlCover.fromJson(_map(customization['cover'])),
      mosaicUrl: _str(customization['mosaic']),
      subtitles: _unwrap(meta['subtitles'], 'subtitle')
          .map((s) => SlSubtitle.fromJson(_map(s)))
          .toList(),
      languages: _unwrap(meta['language_ids'], 'language_id')
          .map((l) => l is String ? l : _str(_map(l)['language_id']))
          .where((l) => l.isNotEmpty)
          .toList(),
      playlists: _unwrap(meta['playlists'], 'playlist').indexed.map((entry) {
        final p = _map(entry.$2);
        return SlMediaPlaylist(
          id: _str(p['playlist_id']),
          name: _str(p['name']),
          type: _str(p['type']),
          position: _int(p['position']) == 0 ? entry.$1 + 1 : _int(p['position']),
        );
      }).toList(),
      keywords: _unwrap(_map(meta['keywords'])['standard_keywords'], 'standard_keyword')
          .map(_str)
          .where((k) => k.isNotEmpty)
          .toList(),
      statistics: SlStatistics.fromJson(_map(media['statistics'])),
      manifestUrl: manifests.isEmpty ? null : manifests.first,
      raw: media,
    );
  }
}

/// Une page de `/ws/playlist`.
class SlPlaylistPage {
  const SlPlaylistPage({
    required this.playlistId,
    required this.name,
    required this.medias,
    required this.size,
    required this.offset,
    required this.limit,
    this.language = '',
    this.totalDurationSec = 0,
    this.raw = const {},
  });

  final String playlistId;
  final String name;
  final String language;

  /// Taille de la playlist **entière**, pas de la page.
  ///
  /// C'est elle qui pilote la pagination et l'état « fin de liste » : sonder
  /// une page vide coûte un appel de plus à chaque parcours, et la plateforme
  /// les compte.
  final int size;
  final double totalDurationSec;
  final List<SlMedia> medias;
  final int offset;
  final int limit;
  final Map<String, dynamic> raw;

  /// Décalage de la page suivante, ou `null` s'il n'y en a plus.
  int? get nextOffset {
    final next = offset + limit;
    return medias.isNotEmpty && next < size ? next : null;
  }

  bool get hasMore => nextOffset != null;

  factory SlPlaylistPage.fromJson(
    Map<String, dynamic> raw, {
    required int offset,
    required int limit,
  }) {
    final playlist = _map(raw['playlist'] ?? raw);
    final meta = _map(playlist['metadata']);
    return SlPlaylistPage(
      playlistId: _str(meta['playlist_id']),
      name: _str(meta['name']),
      language: _str(meta['language']),
      size: _int(meta['size']),
      totalDurationSec: _num(meta['total_duration']),
      medias: _unwrap(playlist['medias'], 'media')
          .map((m) => SlMedia.fromJson({'media': m}))
          .toList(),
      offset: offset,
      limit: limit,
      raw: playlist,
    );
  }
}

/// Une playlist telle que `/ws/playlists` la liste.
class SlPlaylistSummary {
  const SlPlaylistSummary({
    required this.id,
    required this.name,
    this.description = '',
    this.language = '',
    this.totalDurationSec = 0,
    this.viewPosition = 0,
    this.mediaCount = 0,
    this.raw = const {},
  });

  final String id;
  final String name;
  final String description;
  final String language;
  final double totalDurationSec;
  final int viewPosition;
  final int mediaCount;
  final Map<String, dynamic> raw;

  factory SlPlaylistSummary.fromJson(Map<String, dynamic> raw) {
    final p = _map(raw['playlist'] ?? raw);
    return SlPlaylistSummary(
      id: _str(p['playlist_id'] ?? p['id']),
      name: _str(p['name']),
      description: _str(p['description']),
      language: _str(p['language']),
      totalDurationSec: _num(p['total_duration']),
      viewPosition: _int(p['view_position']),
      mediaCount: _int(p['size'] ?? p['media_count']),
      raw: p,
    );
  }
}

/// Dernière position vue par un spectateur sur un média.
class SlResume {
  const SlResume({required this.mediaId, required this.positionSec});

  final String mediaId;

  /// Position en secondes. 0 quand le spectateur est inconnu de la plateforme.
  final double positionSec;

  Duration get position => Duration(milliseconds: (positionSec * 1000).round());
}

/// Exposés pour les paquets qui lisent d'autres réponses de la plateforme.
List<dynamic> unwrapSlList(Object? raw, String key) => _unwrap(raw, key);
String slString(Object? v) => _str(v);
double slNumber(Object? v) => _num(v);
bool slBool(Object? v) => _bool(v);
Map<String, dynamic> slMap(Object? v) => _map(v);
