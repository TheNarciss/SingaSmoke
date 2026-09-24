# SingaSmoke

App iPhone qui répond en quelques secondes à deux questions, partout à Singapour :

1. **Est-ce que je risque une amende là où je suis ?** La carte de statut en haut de l'écran teste ta position contre 15 000 lieux non-fumeurs : zone d'Orchard Road, parcs, plages, réservoirs, 5 m autour des arrêts de bus, aires de jeux, coins fitness, terrains de sport, écoles, hôpitaux, hawker centres, gares routières, parkings à étages…
2. **Où est le spot autorisé le plus proche ?** Carrés jaunes officiels NEA, zones fumeurs de Changi Airport, coins fumeurs cartographiés sur OpenStreetMap, triés par distance **à pied** (itinéraires Apple), avec guidage dans l'app ou dans Plans / Google Maps.

Plus un mode **Buy** : les ~4 200 points de vente de tabac sous licence HSA, filtrables par type (convenience store, supermarket, minimart, petrol station, kopitiam, other).

Un seul écran, la carte d'abord, dans l'esprit des apps de trottinettes comme Lime : fond de carte sobre, zones interdites en rouge, pastilles vertes pour les spots, carte de statut en haut, cartes des spots les plus proches à faire défiler en bas, sélecteur Smoke / Buy.

Pas de compte, pas de serveur, pas de clé API, aucun suivi. iPhone uniquement, iOS 17 minimum, interface en anglais, clair et sombre, VoiceOver et tailles de texte dynamiques.

> Les données peuvent être périmées. Fie-toi toujours à la signalétique sur place : panneaux et marquage jaune au sol.

## Ce que l'app sait, et ce qu'elle ne peut pas savoir

| Couche | Source | Fiabilité |
|---|---|---|
| 52 carrés jaunes d'Orchard Road, avec la photo NEA | NEA (data.gov.sg) | officiel |
| 32 zones fumeurs de Changi Airport | Changi Airport Group (page web lue par le script) | officiel, **position approximative** : CAG décrit en mots (« opposite Gate B10 »), le repère est posé sur la porte citée (OSM) ou au centre du terminal |
| ~90 coins fumeurs ailleurs | OpenStreetMap | indicatif |
| Zone non-fumeur d'Orchard Road, hawker centres | NEA | officiel |
| Parcs et jardins | NParks | officiel |
| Arrêts de bus, aires de jeux, fitness, terrains, écoles, hôpitaux, plages, réservoirs, food courts, parkings à étages, gares routières, stades | OpenStreetMap, filtrés sur la liste des lieux interdits par le *Smoking (Prohibition in Certain Places) Regulations* | indicatif |
| ~4 200 points de vente | HSA (data.gov.sg), géocodés par code postal (OSM puis OneMap) | officiel, position au bâtiment |

Il n'existe **aucun registre national des coins fumeurs** : hors Orchard et Changi, ceux des coffee shops, bureaux et zones industrielles ne sont publiés nulle part. Et une carte ne peut pas voir l'intérieur d'un bâtiment, un passage couvert, une passerelle, un void deck HDB ou les 5 m autour d'une entrée, où fumer est interdit aussi. D'où un verdict à quatre états plutôt qu'un simple « OK / interdit » :

- 🔴 **You're in a no-smoking zone** : lieu non-fumeur connu, avec la direction de la sortie et le spot le plus proche ;
- 🟠 **Edge of a no-smoking zone** : le bord est dans la marge d'erreur du GPS ;
- 🟢 **Designated smoking area** : carré jaune NEA (qui l'emporte sur la zone d'Orchard autour) ou coin fumeur signalé ;
- **Zone OK: no known restriction here** : en plein air, hors abri, loin des entrées, c'est en principe autorisé.

Amende : 200 S$ sur le champ, jusqu'à 1 000 S$ au tribunal (NEA).

## Installer l'app sur l'iPhone, sans Xcode

Comme pour Tangent : GitHub Actions compile l'app sur un Mac et l'envoie sur **TestFlight**. Un push sur `main` suffit ; depuis la VM :

```bash
gh workflow run ios.yml -R TheNarciss/SingaSmoke -f testflight=true
gh run watch -R TheNarciss/SingaSmoke
```

La mise en place, une seule fois (App ID, profil, fiche App Store Connect, secrets repris de Tangent), est détaillée dans **[docs/testflight.md](docs/testflight.md)**.

## Régénérer les données

Tout est embarqué dans l'app (`SingaSmoke/Resources/Data/`), rien n'est téléchargé au lancement.

**Sans rien installer** : GitHub → Actions → **Data** → Run workflow. Le job récupère les sources, vérifie le résultat, commite les fichiers et relance un build TestFlight. Il tourne aussi seul le 1er de chaque mois, ce qui garde le build TestFlight à jour avant son expiration à 90 jours.

**En local ou sur la VM** (Node 20+, aucune dépendance) :

```bash
npm run data          # fetch → geocode → build → check
```

| Étape | Ce qu'elle fait |
|---|---|
| `scripts/fetch.mjs` | 5 jeux data.gov.sg (NEA, NParks, HSA), 9 requêtes Overpass (OSM), la page Changi → `data/raw/` |
| `scripts/geocode.mjs` | code postal → coordonnées : OSM d'abord, OneMap pour le reste, cache dans `data/sources/geocache.json` (commité : une relance ne redemande que les nouveaux) |
| `scripts/build.mjs` | produit `spots.geojson`, `zones.geojson`, `retailers.geojson`, `meta.json` |
| `scripts/check.mjs` | garde-fous : ION Orchard doit tomber dans la zone d'Orchard, le Botanic Gardens dans un parc, chaque carré jaune dans la zone d'Orchard, etc. Échoue plutôt que de livrer des données fausses. |

Les fichiers GeoJSON s'affichent directement sur une carte dans GitHub : c'est le moyen le plus simple de vérifier une mise à jour.

## Le code

```
SingaSmoke/                  l'app (SwiftUI, MapKit, CoreLocation)
  App/                       point d'entrée, avertissement au premier lancement
  Model/                     état de l'app, localisation « quand l'app est ouverte », itinéraires Apple
  Map/                       MKMapView : pastilles, regroupement des 4 200 points, zones en rouge
  Features/Home              l'écran principal : carte, carte de statut, cartes des spots proches
  Features/Smoke|Buy|Navigation|About   fiches, listes, guidage à pied, infos
  Shared/Theme.swift         le style : couleurs, cartes flottantes, boutons pilule
  Resources/Data/            les données générées
Packages/SingaSmokeCore/     toute la logique, sans interface : géométrie, zones, verdict, formats
  Tests/                     tests unitaires
scripts/                     récupération et transformation des données (Node), captures d'écran CI
project.yml                  le projet Xcode décrit en texte (XcodeGen)
.github/workflows/           ios.yml (tests, build, captures d'écran sur les PR, TestFlight), data.yml (données)
```

La logique vit dans un package Swift séparé, Foundation seulement : elle se teste sans simulateur, sur macOS comme sur Linux.

```bash
cd Packages/SingaSmokeCore && swift test
```

Les tests couvrent le point-in-polygon (trous, formes concaves, anneaux ouverts ou fermés), les distances (haversine, projection locale, caps), les zones avec leur marge (5 m autour d'un arrêt de bus, d'une école), l'index spatial comparé à une recherche exhaustive, le verdict et ses priorités, les formats, et les vraies données embarquées. Ils tournent à chaque push avant la compilation de l'app.

Pour ouvrir le projet dans Xcode quand même : `brew install xcodegen && xcodegen generate && open SingaSmoke.xcodeproj`.

## Vie privée

- Localisation demandée à l'ouverture, en mode « quand l'app est active » seulement ; arrêtée dès que l'app passe en arrière-plan.
- Aucun compte, aucun traceur, aucune statistique. Le manifeste de confidentialité déclare zéro donnée collectée.
- Réseau : fond de carte et itinéraires d'Apple, photos NEA. Le verdict, les listes et les zones marchent hors ligne (distances alors estimées, marquées « ≈ »).

## Plus tard

Signalements par les utilisateurs (« coin fumeur ici », « il n'existe plus »), avec récompenses et connexion Sign in with Apple. Ça demandera un petit backend (la VM de Tangent peut l'héberger) ; l'app est prête à recevoir une source de plus.

## Licences et attributions

Code : MIT. Traitement des données inspiré de [likalight/smokingarea-sg](https://github.com/likalight/smokingarea-sg) (MIT).

Données, qui ne sont pas les nôtres :
- NEA, NParks, HSA : *Contains information from the Designated Smoking Areas, No-Smoking Zones, Hawker Centres, NParks No-Smoking Locations and Listing of Licensed Tobacco Retailers datasets accessed from data.gov.sg, made available under the terms of the [Singapore Open Data Licence version 1.0](https://data.gov.sg/open-data-licence).* Aucun soutien des agences n'est impliqué.
- OpenStreetMap : © contributeurs OpenStreetMap, [ODbL](https://www.openstreetmap.org/copyright). Les fichiers dérivés d'OSM (`zones.geojson`, `spots.geojson`) restent sous ODbL.
- Géocodage : OneMap © Singapore Land Authority.
- Zones fumeurs de Changi : Changi Airport Group.

Application non officielle, sans lien avec NEA, NParks, HSA, SLA ni Changi Airport Group. Tabac : 21 ans minimum ; vapes et e-cigarettes illégales à Singapour.
