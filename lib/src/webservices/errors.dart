/// Erreurs des webservices `/ws/*`.
///
/// Les webservices n'ont **aucune enveloppe d'erreur JSON** : ils répondent
/// `404` avec une page HTML, aussi bien pour un média inconnu que pour une
/// valeur de paramètre erronée ou une IP non autorisée. Laisser filer cette
/// page jusqu'au décodeur JSON donne « FormatException: Unexpected character »,
/// qui ne dit rien de la cause — et l'application affiche « erreur inattendue »
/// à quelqu'un qui attend sa vidéo.
library;

/// Échec d'un appel à un webservice.
class StreamlikeException implements Exception {
  StreamlikeException(this.service, this.statusCode, this.message, {this.hint, this.body});

  /// Le service appelé (`playlist`, `media`, `vote`…).
  final String service;

  /// Code HTTP, ou `null` quand l'appel n'a pas abouti (réseau, délai).
  final int? statusCode;
  final String message;

  /// Piste de diagnostic, quand la forme de l'erreur en suggère une.
  final String? hint;

  /// Début du corps reçu — souvent la page HTML d'erreur.
  final String? body;

  /// L'appel a-t-il des chances d'aboutir en le rejouant ?
  ///
  /// Un 404 de webservice ne se rejoue pas : la cause est dans la requête ou
  /// dans la configuration du compte, jamais passagère. Réessayer en boucle
  /// vide la batterie sans rien améliorer.
  bool get isRetryable => statusCode == null || statusCode! >= 500;

  @override
  String toString() =>
      'StreamlikeException(ws/$service, ${statusCode ?? 'réseau'}): $message'
      '${hint != null ? '\n  → $hint' : ''}';
}
