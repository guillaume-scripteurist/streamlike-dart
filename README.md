# streamlike (Dart)

Client Dart de la plateforme vidéo **Streamlike**. Pur Dart : Flutter (web, iOS,
Android) comme backend Dart. Une seule dépendance, `http`.

Pendant Dart de `@scripteurist/streamlike-node` (serveur) et de
`@scripteurist/streamlike-client` (navigateur). Les trois parlent la même
plateforme et se sont trompés aux mêmes endroits — ce fichier documente les
pièges plutôt que de les répéter.

## Installation

Pas publié sur pub.dev — dépendance par URL git avec tag :

```yaml
dependencies:
  streamlike:
    git:
      url: https://github.com/guillaume-scripteurist/streamlike-dart.git
      ref: v0.1.0
```

## Choisir la porte

| Besoin | Ici |
|---|---|
| Afficher un catalogue, une fiche, une vignette | `StreamlikeWebservices` |
| Jouer une vidéo | `buildPlayerUri` dans une iframe ou une WebView |
| Savoir si un média va se lire | `playabilityOf` |
| Jouer avec un player natif | `fetchStreams` **et** `SlPlaybackReporter` |
| Créer, modifier, supprimer un média | **rien ici** — voir plus bas |

### Ce que ce paquet ne fera jamais

L'**API REST** (`api.streamlike.com`) n'est pas couverte, et ne le sera pas. Une
clé d'API porte tous les droits du compte qui l'a créée : la mettre dans une
application, c'est la donner à quiconque en ouvre le paquet — un `.apk` se
décompresse, un bundle web se lit dans l'inspecteur.

Une application parle à **son** backend ; le backend parle à l'API.

De même, `company_id` adresse le catalogue entier : il reste sur le serveur.
Deux services en sont dispensés et peuvent être appelés depuis un appareil :
`/ws/media` et `/ws/rss`. `/ws/playlist` aussi, tant qu'on lui donne un
`playlist_id` plutôt qu'un `company_id`.

```dart
// Sur un appareil : pas de company_id, donc pas de secret à fuiter.
final ws = StreamlikeWebservices();
await ws.media(mediaId: 'abc');        // autorisé
await ws.playlist(playlistId: 'p1');   // autorisé
await ws.playlists();                  // refusé, AVANT tout appel réseau
```

## Lire un catalogue

```dart
final page = await ws.playlist(playlistId: id, offset: 0, limit: 20, encoded: true);

page.size;        // taille de la playlist ENTIÈRE, pour l'état « fin de liste »
page.nextOffset;  // null quand il n'y a plus rien — pas de page vide à demander
page.hasMore;

await for (final media in ws.iteratePlaylist(playlistId: id, pageSize: 50)) {
  media.duration;                    // Duration
  media.aspectRatio;                 // 16/9 si la plateforme n'a pas calculé
  media.cover.best;                  // la plus grande vignette disponible
  media.statistics.ratingAverage;    // null si personne n'a voté
}
```

**Ne pas appeler `media()` pour chaque entrée d'une liste** : `playlist()` rend
déjà la structure complète de chaque média. C'est la recommandation explicite de
la plateforme, et le premier motif de bridage d'un compte.

## Jouer une vidéo

```dart
final url = buildPlayerUrl(
  SlPlayerTarget.permalink(media.permalink),
  SlPlayerOptions.review.copyWith(pid: 'CFG42', userToken: session.userToken),
);
```

Quatre préréglages : `broadcast` (écran sans personne devant), `preview`
(console), `feed` (carte d'un fil vertical), `review` (relire sa propre vidéo).

Le transport (`postMessage` en web, canal de WebView en natif) reste dehors :
`parsePlayerMessage` et `encodePlayerCommand` fabriquent et lisent les charges
utiles, sans jamais importer `dart:html`. C'est ce qui garde ce paquet
utilisable partout.

```dart
final event = parsePlayerMessage(message.data);
if (event is SlStateEvent && event.state == SlPlayerState.ended) suivante();
```

## Ce média va-t-il se lire ?

```dart
switch (playabilityOf(media)) {
  case SlPlayability.open:
  case SlPlayability.password:      // le player demandera lui-même
  case SlPlayability.restricted:    // dépend de la personne, pas de nous
    afficherLePlayer();
  case SlPlayability.tokenRequired: // il faut un sltoken signé par le serveur
    afficherLaVignetteEtUnMessage();
}
```

## Player natif : compter les lectures

Le player de la plateforme rapporte tout seul. Un player natif ne rapporte
**rien** : le trafic apparaît dans la consommation, les lectures nulle part.

```dart
final streams = await fetchStreams(media.manifestUrl!);
final url = streams.hlsMaster;   // l'entrée à débit 0 — ni la première, ni la plus grosse

final reporter = SlPlaybackReporter(
  mediaId: media.id, duration: media.duration,
  playerName: 'kiosk-mobile', userToken: session.userToken,
);
controller.addListener(() => reporter.onPosition(
  controller.value.position, playing: controller.value.isPlaying));
// au démontage — sinon le dernier segment est perdu :
await reporter.flush();
```

`SlPlaybackReporter` tient les deux règles qui se perdent toujours dans un
widget : **une** balise `o.k` par lecture, et un segment fermé à chaque saut
(sauter de la minute 1 à la minute 40 déclarerait sinon 39 minutes vues).

## Les pièges, et ce que la lib en fait

| Piège | Ce qui se passe vraiment |
|---|---|
| `page` ressemble à un numéro de page | C'est un **décalage**. `pagesize=10&page=10` rend les éléments 10 à 19. La lib expose `offset`/`limit` et traduit. |
| `sortorder=desc` | `up` / `down`. `desc` répond **404**. `SlSortOrder` ne propose que les valeurs valides. |
| Une erreur est du JSON | Une erreur est un **404 en HTML** — identifiant inconnu, valeur invalide ou IP non autorisée, sans distinction. `StreamlikeException` porte l'indice et `isRetryable` dit de ne pas rejouer. |
| `is_tokenized: "0"` | Une chaîne non vide, donc « vrai » pour un `!!` naïf : tout le catalogue passerait pour protégé. |
| Un média sans sous-titres | La clé `subtitles` est **absente**, pas vide. Les listes normalisées ne sont jamais nulles. |
| Le premier flux du manifeste | Le master adaptatif est celui dont `globalbitrate` vaut **0**. |
| Les URL du manifeste | Relatives au protocole (`//cfcdn…`) : préfixées en `https:` ici. |
| `autostart` seul | Les navigateurs refusent la lecture auto **avec le son**. Sans `muted`, l'image reste figée, sans erreur. |
| Plusieurs playlists jointes par `\|` | `\|` ne vaut que pour `videositemap`. `/ws/playlist` veut `playlist_id[]` répété. |
| `user_token` de plus de 64 caractères | Tronqué en silence par la plateforme : deux spectateurs deviendraient la même personne. Tronqué ici aussi, explicitement. |

## Développement

```bash
dart pub get
dart analyze
dart test        # aucun appel réseau
```

## Licence

UNLICENSED — usage interne.
