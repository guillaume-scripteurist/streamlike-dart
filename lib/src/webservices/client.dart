/// Le chemin de **lecture** de Streamlike : les webservices `/ws/*`.
///
/// ## Où ce client a le droit de tourner
///
/// `company_id` adresse le catalogue entier : c'est un secret, et il ne descend
/// **ni dans un navigateur ni sur un téléphone**. Deux services seulement en
/// sont dispensés et peuvent être appelés depuis un appareil : `media` et
/// `rss`. Tout le reste passe par notre propre backend.
///
/// D'où les deux façons de construire ce client :
///
/// ```dart
/// // Sur un appareil : pas de company_id, donc pas de secret à fuiter.
/// final ws = StreamlikeWebservices();
/// await ws.media(mediaId: 'abc');            // autorisé
/// await ws.playlist(playlistId: 'p1');       // autorisé : l'id de playlist suffit
/// await ws.playlists();                      // refusé avant tout appel réseau
///
/// // Sur un serveur Dart :
/// final ws = StreamlikeWebservices(companyId: env['SL_COMPANY_ID']);
/// ```
///
/// ## Trois pièges, tous silencieux
///
/// 1. **`page` est un DÉCALAGE, pas un numéro de page.** `pagesize=10&page=10`
///    rend les éléments 10 à 19. Ce client expose `offset`/`limit` et traduit ;
///    un fil qui avancerait de 1 en 1 afficherait des doublons.
/// 2. **`sortorder` vaut `up` ou `down`.** `desc` répond 404.
/// 3. **Une erreur est un 404 en HTML.** Voir [StreamlikeException].
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media.dart';
import 'errors.dart';

/// Hôte des webservices **et** du player. Service public, aucun jeton n'y transite.
const String streamlikeCdn = 'https://cdn.streamlike.com';

/// Sens du tri. La plateforme dit `up`/`down` ; `asc`/`desc` répondent 404.
enum SlSortOrder {
  up('up'),
  down('down');

  const SlSortOrder(this.value);
  final String value;
}

/// Tris acceptés par `playlist`.
enum SlOrderBy {
  id('id'),
  name('name'),
  duration('duration'),
  vote('vote'),
  hit('hit'),
  lastPlaybackDate('lastplaybackdate'),
  creationDate('creationdate'),
  lastUpdatedDate('lastupdateddate'),
  releaseDate('releasedate'),

  /// L'ordre manuel posé dans le back-office — ce qu'attend une playlist éditorialisée.
  position('position');

  const SlOrderBy(this.value);
  final String value;
}

/// Champs sur lesquels une recherche plein texte porte.
enum SlSearchField {
  id('id'),
  name('name'),
  description('description'),
  credits('credits'),
  keywords('keywords'),
  customs('customs'),
  transcription('transcription'),
  permalink('permalink'),
  subtitle('subtitle');

  const SlSearchField(this.value);
  final String value;
}

/// Client des webservices. Lecture seule, sauf [vote].
class StreamlikeWebservices {
  StreamlikeWebservices({
    this.companyId,
    String? baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  })  : _baseUrl = (baseUrl ?? streamlikeCdn).replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// Identifiant de compte. **Secret** — voir l'en-tête de ce fichier.
  final String? companyId;
  final String _baseUrl;
  final http.Client _http;
  final bool _ownsClient;
  final Duration timeout;

  /// Ferme le client HTTP, s'il a été créé ici.
  ///
  /// Fermer un client fourni par l'appelant couperait les autres requêtes de
  /// l'application qui le partagent.
  void close() {
    if (_ownsClient) _http.close();
  }

  String _requireCompanyId(String? explicit, String service) {
    final id = explicit ?? companyId;
    if (id == null || id.isEmpty) {
      throw StreamlikeException(
        service,
        null,
        'company_id manquant',
        hint: 'Ce service adresse tout le catalogue. Le company_id est un secret : '
            'il reste sur le serveur. Depuis un appareil, appeler notre propre '
            'backend, qui appellera ce service.',
      );
    }
    return id;
  }

  /// URL d'un service, pour la journaliser, la mettre en cache ou la proxifier.
  Uri uri(String service, Map<String, dynamic> params) {
    final query = <String, dynamic>{};
    params.forEach((key, value) {
      if (value == null) return;
      if (value is List) {
        if (value.isEmpty) return;
        query[key] = value.map((v) => v.toString()).toList();
      } else {
        final s = value.toString();
        if (s.isNotEmpty) query[key] = s;
      }
    });
    query.putIfAbsent('f', () => 'json');
    return Uri.parse('$_baseUrl/ws/$service').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _get(String service, Map<String, dynamic> params) async {
    final target = uri(service, params);
    http.Response response;
    try {
      response = await _http.get(target).timeout(timeout);
    } on TimeoutException {
      throw StreamlikeException(service, null, 'délai dépassé (${timeout.inSeconds} s)');
    } catch (err) {
      throw StreamlikeException(service, null, 'échec réseau : $err');
    }

    if (response.statusCode != 200) {
      throw StreamlikeException(
        service,
        response.statusCode,
        'HTTP ${response.statusCode}',
        hint: response.statusCode == 404 ? _hint404(service) : null,
        body: _snippet(response.body),
      );
    }

    // Contrôler la FORME avant de décoder : un 200 peut porter du HTML quand la
    // plateforme sert une page d'erreur sans changer le code.
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    } on FormatException {
      throw StreamlikeException(
        service,
        response.statusCode,
        'réponse non-JSON',
        hint: 'Un 200 non-JSON signale en général une page d\'erreur servie en 200.',
        body: _snippet(response.body),
      );
    }
  }

  static String _snippet(String body) =>
      body.length > 300 ? '${body.substring(0, 300)}…' : body;

  static String _hint404(String service) {
    if (service == 'vote' || service == 'manifest') {
      return '$service exige une IP serveur autorisée (back-office : Sécurité → '
          'Sécurité des webservices), et pour `vote` cette protection ne peut pas '
          'être levée. Un 404 ici veut le plus souvent dire « IP non autorisée », '
          'pas « introuvable ».';
    }
    return 'Un 404 de webservice couvre aussi bien un identifiant inconnu qu\'une '
        'VALEUR de paramètre invalide (par exemple sortorder=desc au lieu de down).';
  }

  // ------------------------------------------------------------------ médias

  /// Tout ce que la plateforme sait d'un média.
  ///
  /// Dispensé de contrôle de référent : c'est l'un des deux seuls services
  /// qu'un appareil peut appeler directement.
  Future<SlMedia> media({String? mediaId, String? permalink}) async {
    if ((mediaId == null || mediaId.isEmpty) && (permalink == null || permalink.isEmpty)) {
      throw StreamlikeException('media', null, 'mediaId ou permalink requis');
    }
    final json = await _get('media', {
      if (mediaId != null && mediaId.isNotEmpty) 'media_id': mediaId,
      if (mediaId == null || mediaId.isEmpty) 'permalink': permalink,
    });
    return SlMedia.fromJson(json);
  }

  /// Une page de médias d'une playlist, d'une vue ou du compte entier.
  ///
  /// **Ne pas appeler [media] pour chaque entrée** : la réponse porte déjà la
  /// même structure, complète. C'est la recommandation explicite de la
  /// plateforme, et le premier motif de bridage d'un compte.
  Future<SlPlaylistPage> playlist({
    String? playlistId,
    List<String>? playlistIds,
    String? viewId,
    String? companyId,
    int offset = 0,
    int limit = 10,
    SlOrderBy? orderBy,
    SlSortOrder? sortOrder,
    String? query,
    List<SlSearchField>? searchFields,
    String? language,
    String? country,
    bool? encoded,
    bool? multipleAudio,
    bool forcePlaylist = false,
    List<String>? notMediaIds,
    List<String>? notPlaylistIds,
    List<String>? notViewIds,
  }) async {
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit < 1 ? 1 : limit;

    final ids = <String>[
      if (playlistId != null && playlistId.isNotEmpty) playlistId,
      ...?playlistIds?.where((id) => id.isNotEmpty),
    ];

    final params = <String, dynamic>{
      // Une seule playlist : `playlist_id`. Plusieurs : `playlist_id[]` répété.
      // Le séparateur `|` ne vaut que pour `videositemap` ; ici il rend un 404.
      if (ids.length == 1) 'playlist_id': ids.first,
      if (ids.length > 1) 'playlist_id[]': ids,
      if (viewId != null && viewId.isNotEmpty) 'view_id': viewId,
      'page': safeOffset,
      'pagesize': safeLimit,
      if (orderBy != null) 'orderby': orderBy.value,
      if (sortOrder != null) 'sortorder': sortOrder.value,
      if (query != null && query.isNotEmpty) 'query': query,
      if (searchFields != null && searchFields.isNotEmpty)
        'search_fields[]': searchFields.map((f) => f.value).toList(),
      if (language != null && language.isNotEmpty) 'lng': language,
      if (country != null && country.isNotEmpty) 'country': country,
      if (encoded != null) 'encoded': encoded ? '1' : '0',
      if (multipleAudio != null) 'multiple_audio': multipleAudio ? '1' : '0',
      if (forcePlaylist) 'forceplaylist': '1',
      if (notMediaIds != null && notMediaIds.isNotEmpty) 'not_media_ids[]': notMediaIds,
      if (notPlaylistIds != null && notPlaylistIds.isNotEmpty) 'not_playlist_ids[]': notPlaylistIds,
      if (notViewIds != null && notViewIds.isNotEmpty) 'not_view_ids[]': notViewIds,
    };

    if (ids.isEmpty && (viewId == null || viewId.isEmpty)) {
      params['company_id'] = _requireCompanyId(companyId, 'playlist');
    } else if (companyId != null && companyId.isNotEmpty) {
      params['company_id'] = companyId;
    }

    final json = await _get('playlist', params);
    return SlPlaylistPage.fromJson(json, offset: safeOffset, limit: safeLimit);
  }

  /// Parcourt une playlist entière, page après page.
  ///
  /// S'arrête sur la taille annoncée plutôt que sur une page vide : demander
  /// une page de trop à chaque parcours est exactement ce que la plateforme
  /// compte. Le plafond protège d'une taille fantaisiste qui ferait tourner la
  /// boucle indéfiniment.
  Stream<SlMedia> iteratePlaylist({
    String? playlistId,
    String? viewId,
    int pageSize = 50,
    int maxPages = 100,
    SlOrderBy? orderBy,
    SlSortOrder? sortOrder,
    bool? encoded,
  }) async* {
    var offset = 0;
    for (var page = 0; page < maxPages; page += 1) {
      final result = await playlist(
        playlistId: playlistId,
        viewId: viewId,
        offset: offset,
        limit: pageSize,
        orderBy: orderBy,
        sortOrder: sortOrder,
        encoded: encoded,
      );
      for (final media in result.medias) {
        yield media;
      }
      final next = result.nextOffset;
      if (next == null) return;
      offset = next;
    }
  }

  /// Médias partageant au moins un mot-clé avec celui-ci.
  ///
  /// Vide quand le média ne porte aucun mot-clé — cas fréquent sur les
  /// catalogues où ce champ n'a jamais été rempli. Ce n'est pas une panne.
  Future<List<SlMedia>> related({
    required String mediaId,
    String? viewId,
    int offset = 0,
    int limit = 6,
  }) async {
    final json = await _get('related', {
      'media_id': mediaId,
      if (viewId != null && viewId.isNotEmpty) 'view_id': viewId,
      'page': offset,
      'pagesize': limit,
    });
    final rows = slMap(json['related'])['medias'] ??
        slMap(json['playlist'])['medias'] ??
        json['medias'];
    return unwrapSlList(rows, 'media')
        .map((m) => SlMedia.fromJson({'media': m}))
        .toList();
  }

  // --------------------------------------------------------------- playlists

  /// Les playlists en ligne du compte, ou celles d'une vue.
  ///
  /// Exige le `company_id` : à appeler depuis un serveur.
  Future<List<SlPlaylistSummary>> playlists({
    String? companyId,
    String? viewId,
    int? offset,
    int? limit,
  }) async {
    final json = await _get('playlists', {
      'company_id': _requireCompanyId(companyId, 'playlists'),
      if (viewId != null && viewId.isNotEmpty) 'view_id': viewId,
      if (offset != null) 'page': offset,
      if (limit != null) 'pagesize': limit,
    });
    final rows = slMap(json['playlists'])['playlist'] ?? json['playlists'];
    return unwrapSlList(rows is List ? rows : const [], 'playlist')
        .map((p) => SlPlaylistSummary.fromJson(slMap(p)))
        .toList();
  }

  // -------------------------------------------------------- lecture et votes

  /// Dernière position vue par un spectateur sur un média.
  ///
  /// N'a de valeur que si le **même** `userToken` a été passé au player : c'est
  /// lui qui fait enregistrer les positions. Sans cela le service répond, mais
  /// toujours 0 — un « reprendre la lecture » qui ramène systématiquement au
  /// début vient presque toujours de là.
  Future<SlResume> resume({required String mediaId, required String userToken}) async {
    final json = await _get('resume', {'media_id': mediaId, 'user_token': userToken});
    final node = slMap(json['resume'] ?? json);
    return SlResume(
      mediaId: slString(node['media_id']).isEmpty ? mediaId : slString(node['media_id']),
      positionSec: slNumber(node['position'] ?? node['timecode'] ?? node['resume']),
    );
  }

  /// Nombre de lectures en cours sur un média.
  Future<int> nowPlaying(String mediaId) async {
    final json = await _get('nowplaying', {'media_id': mediaId});
    final node = json['nowplaying'] ?? json;
    if (node is num) return node.round();
    final map = slMap(node);
    return slNumber(map['count'] ?? map['nowplaying'] ?? map['value']).round();
  }

  /// Enregistre une note de 0 à 5.
  ///
  /// **Serveur uniquement**, et pour deux raisons distinctes : l'IP appelante
  /// doit être autorisée (protection non désactivable), et la déduplication est
  /// à notre charge. La plateforme ne stocke qu'un agrégat — « qui a aimé quoi »
  /// appartient à notre base, et c'est elle qu'il faut interroger avant
  /// d'appeler, sans quoi un seul enthousiaste déplace la moyenne à lui seul.
  Future<Map<String, dynamic>> vote({
    required String mediaId,
    required int value,
    String? companyId,
  }) {
    return _get('vote', {
      'company_id': _requireCompanyId(companyId, 'vote'),
      'media_id': mediaId,
      'value': value.clamp(0, 5),
    });
  }

  /// Description complète des fichiers encodés d'un média.
  ///
  /// **Exige une IP autorisée.** `SlMedia.manifestUrl` porte la même
  /// information sans cette contrainte : c'est presque toujours la bonne voie.
  Future<Map<String, dynamic>> manifest(String mediaId, {String? token}) {
    return _get('manifest', {'media_id': mediaId, if (token != null) 'token': token});
  }

  /// Langues présentes dans le catalogue en ligne.
  Future<List<String>> languages({String? companyId, String? viewId}) async {
    final json = await _get('languages', {
      'company_id': _requireCompanyId(companyId, 'languages'),
      if (viewId != null) 'view_id': viewId,
    });
    final rows = slMap(json['languages'])['language'] ?? json['languages'];
    return unwrapSlList(rows is List ? rows : const [], 'language')
        .map((l) => l is String ? l : slString(slMap(l)['language_id']))
        .where((l) => l.isNotEmpty)
        .toList();
  }
}
