/// « Dois-je poser un player, ou une vignette et un message ? »
///
/// Un catalogue n'est jamais entièrement lisible : certains médias sont
/// protégés par jeton, mot de passe, IP ou domaine référent. Poser le player
/// quand même donne un rectangle noir, et la personne n'a aucun moyen de savoir
/// si c'est le réseau, l'application ou la vidéo.
///
/// Les trois drapeaux arrivent **déjà** dans la liste renvoyée par
/// `/ws/playlist` : la question se tranche au moment du rendu, sans un appel de
/// plus.
library;

import '../models/media.dart';

/// Ce que la protection d'un média impose au rendu.
enum SlPlayability {
  /// Rien à faire : l'URL du player suffit.
  open,

  /// Le player réclamera le mot de passe lui-même — le poser normalement.
  password,

  /// Restreint par IP ou par référent : la lecture dépend de la personne, pas
  /// de nous. Poser le player et ne signaler qu'en cas d'échec réel.
  restricted,

  /// Il faut un `sltoken` frais, signé par le serveur. Une URL nue ne lira pas.
  tokenRequired,
}

/// Classe un média selon sa protection.
///
/// L'ordre des tests compte : un média protégé à la fois par jeton **et** par
/// mot de passe se lit — le player réclame le mot de passe. Tester le jeton
/// d'abord le déclarerait injouable et retirerait de l'écran un média qui se
/// serait très bien affiché.
SlPlayability playabilityOf(SlMedia media) {
  if (media.hasPassword) return SlPlayability.password;
  if (media.isTokenized) return SlPlayability.tokenRequired;
  if (media.isSecured) return SlPlayability.restricted;
  return SlPlayability.open;
}

/// Peut-on poser le player sans autre précaution ?
bool isEmbeddable(SlMedia media) => playabilityOf(media) != SlPlayability.tokenRequired;

extension SlMediaPlayability on SlMedia {
  SlPlayability get playability => playabilityOf(this);
  bool get canEmbed => isEmbeddable(this);
}

/// Ne garde que ce qui se lira.
///
/// `withToken` : à mettre à `true` quand le backend sait signer un `sltoken`
/// pour chaque média — les médias à jeton sont alors conservés.
List<SlMedia> playableOnly(Iterable<SlMedia> medias, {bool withToken = false}) =>
    medias.where((m) => withToken || isEmbeddable(m)).toList();
