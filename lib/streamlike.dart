/// Client Dart de la plateforme vidéo **Streamlike**.
///
/// Pur Dart : utilisable en Flutter (web, iOS, Android) comme dans un backend.
///
/// ## Choisir la bonne porte
///
/// | Besoin | Ici |
/// |---|---|
/// | Afficher un catalogue, une fiche, une vignette | [StreamlikeWebservices] |
/// | Jouer une vidéo | [buildPlayerUri] dans une iframe / WebView |
/// | Savoir si un média se lira | [playabilityOf] |
/// | Jouer avec un player natif | [fetchStreams] **et** [SlPlaybackReporter] |
/// | Créer, modifier, supprimer un média | **rien ici** — voir ci-dessous |
///
/// ## Ce que ce paquet ne fera jamais
///
/// L'**API REST** de Streamlike (`api.streamlike.com`) n'est pas couverte, et
/// ne le sera pas. Une clé d'API porte tous les droits du compte qui l'a créée :
/// la mettre dans une application, c'est la donner à quiconque en ouvre le
/// paquet — un `.apk` se décompresse, un bundle web se lit dans l'inspecteur.
///
/// Une application parle à **son** backend ; le backend parle à l'API.
/// Côté serveur, `@scripteurist/streamlike-node` couvre cette part.
library;

export 'src/analytics/beacons.dart';
export 'src/models/media.dart'
    show
        SlCover,
        SlMedia,
        SlMediaPlaylist,
        SlPlaylistPage,
        SlPlaylistSummary,
        SlResume,
        SlStatistics,
        SlSubtitle;
export 'src/playback/streams.dart';
export 'src/player/embed.dart';
export 'src/player/messages.dart';
export 'src/security/playability.dart';
export 'src/webservices/client.dart';
export 'src/webservices/errors.dart';
