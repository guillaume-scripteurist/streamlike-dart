/// Ce que la lib envoie à Streamlike, et ce qu'elle fait de ses réponses.
///
/// On verrouille ici les pièges qui ne s'annoncent pas : un décalage pris pour
/// un numéro de page, un drapeau « 0 » pris pour vrai, une page HTML passée au
/// décodeur JSON, un master HLS confondu avec un rendu isolé. Chacun donne une
/// application qui a l'air de marcher, jusqu'à la salle.
///
/// Aucun appel réseau : le client HTTP est remplacé.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamlike/streamlike.dart';
import 'package:test/test.dart';

/// Un média minimal, au format exact de la plateforme.
Map<String, dynamic> mediaJson({Map<String, dynamic> global = const {}}) => {
      'metadata': {
        'global': {
          'media_id': 'abc123',
          'name': 'Marie',
          'permalink': 'marie',
          'type': 'video',
          'duration': '137',
          'ratio': '1.7778',
          'is_tokenized': '0',
          'has_password': '0',
          'is_secured': '0',
          'is_multiple_audio': '1',
          'description': '',
          ...global,
        },
        'share': {'universal_url': 'https://exemple.test/marie'},
        'customization': {
          'cover': {'thumbnaillarge_url': 'https://img.test/l.jpg'}
        },
        'playlists': [
          {
            'playlist': {'playlist_id': 'p1', 'name': 'Soirée', 'position': '2'}
          }
        ],
        // Pas de clé `subtitles` : la plateforme OMET les blocs vides.
      },
      'statistics': {'media_access': '42', 'rating_hits': '4', 'rating_totalvalue': '18'},
      'html5_sources': [
        {
          'html5_source': {'type': 'streamlike_html5', 'manifest': '//cfcdn.test/m.json'}
        }
      ],
    };

/// Client HTTP qui note les URL appelées et rend une réponse fixe.
({MockClient client, List<Uri> calls}) mockJson(
  Object payload, {
  int status = 200,
  String contentType = 'application/json',
}) {
  final calls = <Uri>[];
  final client = MockClient((request) async {
    calls.add(request.url);
    final body = payload is String ? payload : jsonEncode(payload);
    return http.Response(body, status, headers: {'content-type': contentType});
  });
  return (client: client, calls: calls);
}

void main() {
  group('webservices', () {
    test('page est un décalage, pas un numéro de page', () async {
      final mock = mockJson({
        'playlist': {
          'metadata': {'size': '100'},
          'medias': <dynamic>[]
        }
      });
      final ws = StreamlikeWebservices(httpClient: mock.client);

      await ws.playlist(playlistId: 'p1', offset: 20, limit: 10);

      // `page=2` afficherait les éléments 2 à 11 : des doublons, et personne ne
      // s'en aperçoit avant la troisième page.
      expect(mock.calls.single.queryParameters['page'], '20');
      expect(mock.calls.single.queryParameters['pagesize'], '10');
    });

    test('plusieurs playlists partent en playlist_id[] répété', () async {
      final mock = mockJson({
        'playlist': {
          'metadata': {'size': '0'},
          'medias': <dynamic>[]
        }
      });
      final ws = StreamlikeWebservices(httpClient: mock.client);

      await ws.playlist(playlistIds: ['a', 'b']);

      // Le séparateur `|` ne vaut que pour le sitemap ; ici il rend un 404.
      expect(mock.calls.single.queryParametersAll['playlist_id[]'], ['a', 'b']);
    });

    test('un 404 HTML devient une exception qui explique', () async {
      final mock = mockJson('<html>Not found</html>', status: 404, contentType: 'text/html');
      final ws = StreamlikeWebservices(httpClient: mock.client, companyId: 'c1');

      await expectLater(
        ws.vote(mediaId: 'abc', value: 5),
        throwsA(isA<StreamlikeException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            // `vote` ne peut pas être dispensé de liste blanche : c'est la
            // première piste à donner, pas « média introuvable ».
            .having((e) => e.hint, 'hint', contains('IP serveur autorisée'))
            // Un 404 de webservice ne se rejoue pas : la cause est dans la
            // requête ou dans le compte, jamais passagère.
            .having((e) => e.isRetryable, 'isRetryable', isFalse)),
      );
    });

    test('company_id manquant est refusé AVANT tout appel réseau', () async {
      final calls = <Uri>[];
      final ws = StreamlikeWebservices(
        httpClient: MockClient((r) async {
          calls.add(r.url);
          return http.Response('{}', 200);
        }),
      );

      await expectLater(ws.playlists(), throwsA(isA<StreamlikeException>()));
      // Le secret n'existe pas sur un appareil : autant le dire tout de suite
      // plutôt que de laisser partir une requête qui reviendra en 404 muet.
      expect(calls, isEmpty);
    });

    test('un média est aplati, drapeaux « 0 » compris', () async {
      final mock = mockJson({'media': mediaJson()});
      final ws = StreamlikeWebservices(httpClient: mock.client);

      final media = await ws.media(mediaId: 'abc123');

      expect(media.id, 'abc123');
      expect(media.durationSec, 137);
      expect(media.duration, const Duration(seconds: 137));
      // "0" est une chaîne non vide : le prendre pour vrai masquerait tout le
      // catalogue derrière un message « média protégé ».
      expect(media.isTokenized, isFalse);
      expect(media.isMultipleAudio, isTrue);
      // Bloc absent -> liste vide, jamais null : le rendu ne doit pas s'arrêter.
      expect(media.subtitles, isEmpty);
      expect(media.playlists.single.id, 'p1');
      expect(media.statistics.playbacks, 42);
      expect(media.statistics.ratingAverage, 4.5);
      expect(media.manifestUrl, '//cfcdn.test/m.json');
      expect(media.cover.best, 'https://img.test/l.jpg');
    });

    test('un média sans note rend null, pas zéro', () {
      const stats = SlStatistics();
      // Zéro se dessine comme « très mauvais » ; il n'y a simplement pas d'avis.
      expect(stats.ratingAverage, isNull);
    });

    test('un rapport d\'image absent retombe sur 16/9', () async {
      final mock = mockJson({
        'media': mediaJson(global: {'ratio': '0'})
      });
      final ws = StreamlikeWebservices(httpClient: mock.client);

      final media = await ws.media(mediaId: 'abc123');

      // Un rapport nul ferait une boîte de hauteur zéro : vidéo invisible.
      expect(media.aspectRatio, closeTo(16 / 9, 0.001));
    });

    test('la pagination s\'arrête sur la taille, sans demander de page vide', () async {
      var pages = 0;
      final client = MockClient((request) async {
        final offset = int.parse(request.url.queryParameters['page']!);
        pages += 1;
        final medias = offset < 3
            ? [
                {
                  'media': mediaJson(global: {'media_id': 'm$offset'})
                }
              ]
            : <dynamic>[];
        return http.Response(
          jsonEncode({
            'playlist': {
              'metadata': {'size': '3'},
              'medias': medias
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final ws = StreamlikeWebservices(httpClient: client);

      final ids = await ws.iteratePlaylist(playlistId: 'p1', pageSize: 1).map((m) => m.id).toList();

      expect(ids, ['m0', 'm1', 'm2']);
      // Trois pages, pas quatre : la quatrième serait un appel pour rien, et la
      // plateforme les compte.
      expect(pages, 3);
    });
  });

  group('player', () {
    test('la configuration de player part en pid', () {
      final uri = buildPlayerUri(
        const SlPlayerTarget.media('abc'),
        const SlPlayerOptions(pid: 'CFG42'),
      );
      expect(uri.queryParameters['med_id'], 'abc');
      expect(uri.queryParameters['pid'], 'CFG42');
    });

    test('le préréglage feed est muet, sans quoi rien ne démarre', () {
      final uri = buildPlayerUri(const SlPlayerTarget.permalink('marie'), SlPlayerOptions.feed);
      expect(uri.queryParameters['autostart'], '1');
      // Les navigateurs refusent une lecture automatique avec le son : sans
      // `muted`, la carte reste figée sur sa première image, sans message.
      expect(uri.queryParameters['muted'], '1');
      expect(uri.queryParameters['max_height'], '720');
    });

    test('les paramètres sensibles sont traduits correctement', () {
      final uri = buildPlayerUri(
        const SlPlayerTarget.media('abc'),
        SlPlayerOptions(
          userToken: 'u' * 80,
          token: 'TOK',
          startAt: const Duration(seconds: 42),
          subtitle: '',
          audioLanguage: 'en-ad',
          activeColor: '#FF0000',
          extra: const {'download': true, 'logo': false, 'skin': 'sombre'},
        ),
      );
      // Tronqué à 64 : au-delà la plateforme tronque en silence, et deux
      // spectateurs deviendraient la même personne dans les statistiques.
      expect(uri.queryParameters['user_token']!.length, 64);
      expect(uri.queryParameters['sltoken'], 'TOK');
      expect(uri.queryParameters['streamlike_mp_starttc'], '42');
      expect(uri.queryParameters['subtitle'], '0');
      expect(uri.queryParameters['audio_lng'], 'en-ad');
      // Le `#` couperait l'URL au fragment : tout ce qui suit disparaîtrait.
      expect(uri.queryParameters['active_color'], 'FF0000');
      expect(uri.queryParameters['download'], '1');
      expect(uri.queryParameters['logo'], '0');
    });

    test('les messages du player sont lus, le reste est ignoré', () {
      expect(parsePlayerMessage('["sl-state","ended"]'), isA<SlStateEvent>());
      expect((parsePlayerMessage('["sl-state","ended"]')! as SlStateEvent).state,
          SlPlayerState.ended);
      expect((parsePlayerMessage('["sl-progress",12.5]')! as SlProgressEvent).seconds, 12.5);
      // Une page reçoit des messages de bien d'autres sources : les traiter
      // comme des événements de lecture ferait sauter des vidéos.
      expect(parsePlayerMessage('bonjour'), isNull);
      expect(parsePlayerMessage({'type': 'autre-chose'}), isNull);
      expect(parsePlayerMessage('["sl-state","inconnu"]'), isNull);
    });

    test('les commandes sont sérialisées comme le player les attend', () {
      expect(encodePlayerCommand(SlPlayerCommand.play), '["play"]');
      expect(encodeSeek(const Duration(milliseconds: 30400)), '["seek",30.4]');
      expect(encodeVolume(2), '["volume",1.0]');
    });
  });

  group('protections', () {
    SlMedia withFlags({bool token = false, bool password = false, bool secured = false}) =>
        SlMedia(
          id: 'x',
          name: 'x',
          permalink: 'x',
          isTokenized: token,
          hasPassword: password,
          isSecured: secured,
        );

    test('la lisibilité se tranche sur les drapeaux déjà reçus', () {
      expect(playabilityOf(withFlags()), SlPlayability.open);
      expect(playabilityOf(withFlags(token: true)), SlPlayability.tokenRequired);
      // Jeton ET mot de passe : le player réclame le mot de passe, ça se lit.
      // Tester le jeton d'abord retirerait de l'écran un média qui s'affichait.
      expect(playabilityOf(withFlags(token: true, password: true)), SlPlayability.password);
      expect(playabilityOf(withFlags(secured: true)), SlPlayability.restricted);

      expect(isEmbeddable(withFlags(token: true)), isFalse);
      expect(isEmbeddable(withFlags(secured: true)), isTrue);
      expect(playableOnly([withFlags(), withFlags(token: true)]).length, 1);
      expect(playableOnly([withFlags(), withFlags(token: true)], withToken: true).length, 2);
    });
  });

  group('flux', () {
    test('le master HLS se reconnaît à son débit nul', () {
      final streams = parseManifest({
        'idevicev2': [
          {'globalbitrate': 320, 'width': 240, 'height': 176, 'url': '//cdn.test/240.m3u8'},
          {'globalbitrate': 0, 'url': '//cdn.test/index.m3u8'},
          {'globalbitrate': 1500, 'width': 1280, 'height': 720, 'url': '//cdn.test/720.m3u8'},
        ],
        'mp4': [
          {'globalbitrate': 1408, 'url': '//cdn.test/x.mp4'}
        ],
      });

      // Ni la première entrée, ni la plus grosse : celle à débit 0.
      expect(streams.hlsMaster, 'https://cdn.test/index.m3u8');
      expect(streams.bestUrl, 'https://cdn.test/index.m3u8');
      expect(streams.hlsRenditions.map((r) => r.bitrate), [320, 1500]);
      expect(streams.progressive.single.url, 'https://cdn.test/x.mp4');
    });

    test('sans master, on retombe sur le meilleur rendu plutôt que sur rien', () {
      final streams = parseManifest({
        'mp4': [
          {'globalbitrate': 500, 'url': '//cdn.test/bas.mp4'},
          {'globalbitrate': 2000, 'url': '//cdn.test/haut.mp4'},
        ],
      });
      expect(streams.hlsMaster, isNull);
      expect(streams.bestUrl, 'https://cdn.test/haut.mp4');
    });

    test('un hls sans taille ne rend pas le master — la redirection est un rendu', () {
      final uri = directFileUri(type: 'hls', mediaId: 'abc');
      expect(uri.path, '/html5/hls/media_id/abc');
    });
  });

  group('audience', () {
    test('les balises portent les bons paramètres', () {
      final play = playbackBeaconUri(
          mediaId: 'abc', streamType: SlStreamType.hls, playerName: 'kiosk', timestamp: 7);
      expect(play.path, '/o.k');
      expect(play.queryParameters['m'], 'abc');
      expect(play.queryParameters['s'], 'hls');

      final eng = engagementBeaconUri(
        mediaId: 'abc',
        duration: const Duration(seconds: 100),
        streamType: SlStreamType.hls,
        qualityHeight: 720,
        playerName: 'kiosk',
        from: const Duration(seconds: 10),
        to: const Duration(seconds: 250),
        timestamp: 7,
      );
      // Borné par la durée : la plateforme rejette un segment qui en sort, et
      // le rejet d'un GET dont personne ne lit la réponse est invisible.
      expect(eng.queryParameters['re'], '100');
      expect(eng.queryParameters['d'], '100');
    });

    test('un segment trop court n\'est pas rapporté', () {
      // Arrive à chaque retour en arrière et à chaque pause immédiate.
      expect(isReportableSegment(Duration.zero, const Duration(milliseconds: 200)), isFalse);
      expect(isReportableSegment(Duration.zero, const Duration(seconds: 2)), isTrue);
    });

    test('une lecture n\'est comptée qu\'une fois, et un saut ferme le segment', () async {
      final hits = <Uri>[];
      final reporter = SlPlaybackReporter(
        mediaId: 'abc',
        duration: const Duration(minutes: 10),
        playerName: 'kiosk-mobile',
        httpClient: MockClient((r) async {
          hits.add(r.url);
          return http.Response('', 200);
        }),
      );

      for (var s = 0; s < 5; s++) {
        reporter.onPosition(Duration(seconds: s), playing: true);
      }
      // Saut franc : ce qui suit est un autre segment, pas 35 minutes vues.
      reporter.onPosition(const Duration(seconds: 300), playing: true);
      reporter.onPosition(const Duration(seconds: 305), playing: true);
      await reporter.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final playbacks = hits.where((u) => u.path == '/o.k');
      expect(playbacks.length, 1, reason: 'une lecture = une balise o.k');
      expect(hits.where((u) => u.path == '/eng.k'), isNotEmpty);
    });
  });
}
