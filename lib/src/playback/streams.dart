/// Du média au flux jouable, pour un player qui n'est pas celui de Streamlike.
///
/// `SlMedia.manifestUrl` pointe vers un index JSON de **tous** les fichiers
/// encodés. On y trouve le master HLS — celui qu'on donne à un player natif —
/// mais il ne s'annonce pas par son nom : il se reconnaît à son débit.
/// **L'entrée dont `globalbitrate` vaut 0 est le master adaptatif**, les autres
/// sont des rendus isolés.
///
/// Prendre la première de la liste, ou la plus grosse, donne un player bloqué
/// sur une seule qualité : ça marche au bureau, et ça casse sur le réseau d'une
/// salle ou en 4G, sans message d'erreur — juste une vidéo qui met vingt
/// secondes à démarrer.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media.dart';
import '../webservices/errors.dart';

/// Un fichier encodé, tel que le manifeste le décrit.
class SlRendition {
  const SlRendition({
    required this.url,
    required this.group,
    this.bitrate = 0,
    this.width = 0,
    this.height = 0,
  });

  /// URL absolue en https — les URL du manifeste sont relatives au protocole.
  final String url;

  /// Groupe d'origine : `idevicev2`, `mp4`, `mp4low`…
  final String group;

  /// Débit global en kbps. **0 désigne le master adaptatif**, pas un fichier muet.
  final int bitrate;

  /// Valeurs de l'encodeur, pas la résolution d'affichage.
  final int width;
  final int height;
}

/// Ce qu'un player peut jouer, une fois le manifeste lu.
class SlStreams {
  const SlStreams({
    this.hlsMaster,
    this.hlsRenditions = const [],
    this.progressive = const [],
    this.all = const [],
  });

  /// Master HLS adaptatif, ou `null` si le média n'en publie pas.
  ///
  /// C'est **la** valeur à donner à un player natif.
  final String? hlsMaster;

  /// Rendus HLS isolés, master exclu, du plus léger au plus lourd.
  final List<SlRendition> hlsRenditions;

  /// Fichiers progressifs, du plus léger au plus lourd.
  final List<SlRendition> progressive;

  final List<SlRendition> all;

  /// La meilleure URL disponible, en préférant l'adaptatif.
  ///
  /// Un player laissé sur un rendu fixe ne s'adapte pas au réseau : sur mobile,
  /// c'est la différence entre une vidéo qui démarre et une vidéo qui tourne.
  String? get bestUrl {
    if (hlsMaster != null) return hlsMaster;
    if (hlsRenditions.isNotEmpty) return hlsRenditions.last.url;
    if (progressive.isNotEmpty) return progressive.last.url;
    return null;
  }
}

const _hlsGroups = {'idevicev2', 'idevicev1'};
const _progressiveGroups = {'mp4', 'mp4low', 'webm'};

String _absolute(Object? raw) {
  final value = slString(raw).trim();
  if (value.isEmpty) return '';
  // `//cfcdn…` : sans préfixe, la chaîne n'est pas une URL pour un client HTTP
  // hors navigateur — et l'erreur ne parle pas de protocole.
  return value.startsWith('//') ? 'https:$value' : value;
}

/// Lit un manifeste déjà téléchargé.
///
/// Séparé du téléchargement à dessein : un manifeste se met en cache, et le
/// relire ne doit pas coûter un aller-retour réseau.
SlStreams parseManifest(Map<String, dynamic> manifest) {
  final all = <SlRendition>[];
  manifest.forEach((group, entries) {
    if (entries is! List) return;
    for (final entry in entries) {
      final map = slMap(entry);
      final url = _absolute(map['url']);
      if (url.isEmpty) continue;
      all.add(SlRendition(
        url: url,
        group: group,
        bitrate: slNumber(map['globalbitrate']).round(),
        width: slNumber(map['width']).round(),
        height: slNumber(map['height']).round(),
      ));
    }
  });

  final hls = all.where((r) => _hlsGroups.contains(r.group)).toList();
  final masters = hls.where((r) => r.bitrate == 0);

  return SlStreams(
    hlsMaster: masters.isEmpty ? null : masters.first.url,
    hlsRenditions: hls.where((r) => r.bitrate > 0).toList()
      ..sort((a, b) => a.bitrate.compareTo(b.bitrate)),
    progressive: all.where((r) => _progressiveGroups.contains(r.group)).toList()
      ..sort((a, b) => a.bitrate.compareTo(b.bitrate)),
    all: all,
  );
}

/// Télécharge puis lit le manifeste pointé par [SlMedia.manifestUrl].
Future<SlStreams> fetchStreams(
  String manifestUrl, {
  http.Client? httpClient,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final url = _absolute(manifestUrl);
  if (url.isEmpty) {
    throw StreamlikeException('manifest', null, 'URL de manifeste vide');
  }
  final client = httpClient ?? http.Client();
  try {
    final response = await client.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode != 200) {
      throw StreamlikeException('manifest', response.statusCode, 'HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    return parseManifest(decoded is Map ? Map<String, dynamic>.from(decoded) : {});
  } on StreamlikeException {
    rethrow;
  } catch (err) {
    throw StreamlikeException('manifest', null, 'manifeste illisible : $err');
  } finally {
    if (httpClient == null) client.close();
  }
}

/// URL de redirection vers le meilleur fichier pour une taille cible.
///
/// La plateforme répond `302` vers le fichier retenu. **Sans `width`/`height`,
/// un `hls` rend UN rendu, pas le master adaptatif** — le player restera sur
/// une seule qualité. Pour du natif adaptatif, passer par [fetchStreams].
Uri directFileUri({
  required String type,
  String? mediaId,
  String? permalink,
  int? width,
  int? height,
  String baseUrl = 'https://cdn.streamlike.com',
}) {
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  final ref = mediaId != null && mediaId.isNotEmpty
      ? 'media_id/${Uri.encodeComponent(mediaId)}'
      : 'permalink/${Uri.encodeComponent(permalink ?? '')}';
  final size = (width != null && height != null) ? '/width/$width/height/$height' : '';
  return Uri.parse('$base/html5/$type/$ref$size');
}
