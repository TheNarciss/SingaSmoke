# Mettre SingaSmoke sur ton iPhone (TestFlight, sans Xcode)

Même principe que Tangent : c'est un Mac de GitHub qui compile, signe et envoie l'app sur TestFlight. Tu ne fais qu'une série de réglages une seule fois, sur les sites d'Apple et dans les secrets GitHub. Aucune de ces valeurs ne passe par un chat.

Une VM Linux ne peut pas compiler une app iPhone (Apple l'impose : macOS + Xcode). Depuis la VM, tu **déclenches** le build sur le Mac de GitHub avec `gh` ; tu ne compiles rien toi-même.

## 1. Apple Developer (developer.apple.com → Certificates, Identifiers & Profiles)

| Quoi | Valeur | Où ça sert |
|---|---|---|
| App ID | Identifiers → **+** → App IDs → App. Description `SingaSmoke`, Bundle ID **explicite** `uk.riskybusinesses.singasmoke`. Aucune capacité à cocher. | l'app |
| Profil de provisionnement | Profiles → **+** → Distribution → **App Store Connect** → App ID `SingaSmoke` → le **même certificat Apple Distribution que Tangent** → nom `SingaSmoke App Store` → télécharger le `.mobileprovision` | secret `IOS_PROVISIONING_PROFILE_B64` |

Le certificat Apple Distribution, le Team ID et la clé API App Store Connect sont ceux de Tangent : ils valent pour toutes les apps du compte.

## 2. App Store Connect (appstoreconnect.apple.com)

Apps → **+** → Nouvelle app :
- Plateforme **iOS**, nom **SingaSmoke** (s'il est déjà pris sur l'App Store, `SingaSmoke SG`),
- langue principale **Français**, bundle ID `uk.riskybusinesses.singasmoke`, SKU libre (`singasmoke`), accès complet.

Rien d'autre à remplir pour TestFlight : pas de captures, pas de revue Apple pour les testeurs internes. La question sur le chiffrement est déjà réglée (`ITSAppUsesNonExemptEncryption = NO` dans l'app).

## 3. Les secrets GitHub

Sept secrets dans **TheNarciss/SingaSmoke → Settings → Secrets and variables → Actions**. Six sont les mêmes valeurs que dans Tangent : GitHub ne permet pas de les relire, reprends-les depuis tes fichiers.

Depuis la VM, dans le dossier où sont les fichiers (`gh` doit être connecté : `gh auth status`) :

```bash
R=TheNarciss/SingaSmoke
gh secret set IOS_PROVISIONING_PROFILE_B64 -R $R --body "$(base64 -w0 SingaSmoke_App_Store.mobileprovision)"
gh secret set IOS_CERTIFICATE_P12_B64      -R $R --body "$(base64 -w0 distribution.p12)"
gh secret set APPSTORE_API_KEY_P8_B64      -R $R --body "$(base64 -w0 AuthKey_XXXXXXXXXX.p8)"
# Ces quatre-là demandent la valeur au clavier (rien ne reste dans l'historique) :
gh secret set IOS_CERTIFICATE_PASSWORD -R $R
gh secret set APPLE_TEAM_ID            -R $R
gh secret set APPSTORE_API_KEY_ID      -R $R
gh secret set APPSTORE_API_ISSUER_ID   -R $R
gh secret list -R $R
```

### Si tu n'as plus le `.p12` du certificat

Tu en refais un depuis la VM, sans Mac :

```bash
openssl genrsa -out distribution.key 2048
openssl req -new -key distribution.key -out distribution.csr -subj "/CN=SingaSmoke Distribution/C=FR"
# developer.apple.com → Certificates → + → Apple Distribution → envoyer distribution.csr → télécharger distribution.cer
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -legacy -inkey distribution.key -in distribution.pem -out distribution.p12 -passout pass:UN_MOT_DE_PASSE
```

`-legacy` est nécessaire : sans lui, le trousseau macOS du runner refuse le fichier. Refais ensuite le profil de provisionnement avec ce nouveau certificat.

### Si tu n'as plus la clé API

App Store Connect → Utilisateurs et accès → Intégrations → App Store Connect API → **+**, rôle **App Manager**. Le `.p8` ne se télécharge qu'une fois. Key ID et Issuer ID sont affichés sur la même page.

## 4. Construire et installer

- **Automatique** : chaque push sur la branche par défaut (`main`) compile et envoie un build sur TestFlight.
- **À la main, depuis la VM** :

  ```bash
  gh workflow run ios.yml -R TheNarciss/SingaSmoke -f testflight=true
  gh run watch -R TheNarciss/SingaSmoke      # suivre le build en direct
  ```

  Ou dans GitHub : Actions → iOS → Run workflow.

- **Sur l'iPhone** : App Store Connect → SingaSmoke → TestFlight → Tests internes → crée un groupe et ajoute-toi. Installe l'app **TestFlight** depuis l'App Store : SingaSmoke y apparaît 5 à 30 minutes après l'envoi (le temps du traitement par Apple). Les mises à jour arrivent au même endroit.

Un build TestFlight expire au bout de 90 jours. Le workflow **Data** refait les données le 1er de chaque mois et relance un build, donc l'app reste installable sans que tu y penses.

## Quand ça coince

| Message dans le job | Cause |
|---|---|
| `TestFlight ignoré : secrets manquants` | un des sept secrets n'existe pas (la liste est dans le message) |
| `No profiles for 'uk.riskybusinesses.singasmoke'` | le profil n'est pas celui de cet App ID, ou pas de type App Store |
| `Provisioning profile … doesn't include signing certificate` | le profil a été fait avec un autre certificat que celui du `.p12` |
| `No suitable application records were found` | l'app n'existe pas encore dans App Store Connect (étape 2) |
| `The bundle version must be higher` | un build avec ce numéro existe déjà ; relance le workflow, le numéro suit le compteur d'exécutions |
