# Hindsight Desktop

**Un client macOS indépendant pour [Hindsight](https://github.com/vectorize-io/hindsight).**
Consultez vos sources, recherchez vos souvenirs et gérez votre serveur depuis une
interface sobre. Gratuit, sous [licence MIT](LICENSE). Bêta communautaire, sans
lien officiel avec Vectorize AI, Inc.

[Français](#installer) · [English](#english) · [Téléchargements / Downloads](https://github.com/paabL/hindsight-desktop/releases)

![Hindsight Desktop — exemple avec données fictives](docs/images/hindsight-desktop.png)

## Installer

**macOS 15 ou plus récent.** Prenez le fichier correspondant à votre Mac dans
les téléchargements. Seules les architectures indiquées dans la release sont
prises en charge. Ouvrez le DMG, puis glissez **Hindsight Desktop** dans
**Applications**. Aucun outil de développement n'est nécessaire pour ouvrir l'app.

Cette première bêta n'est **pas notariée par Apple**. macOS peut en empêcher
l'ouverture : après une première tentative, allez dans **Réglages Système →
Confidentialité et sécurité → Ouvrir quand même**, seulement si vous avez
vérifié la provenance du téléchargement. [Aide Apple](https://support.apple.com/102445).
Ne désactivez pas les protections de macOS.

## Premiers pas

1. Ouvrez l'app et choisissez votre langue.
2. Dans **Réglages**, indiquez l'adresse de votre serveur Hindsight déjà installé
   (`http://127.0.0.1:8888` en local). Les fonctions récentes ciblent l'API 1.2.0 ;
   les fonctions disponibles dépendent de votre serveur.
3. Choisissez une banque. Vous pouvez aussi consulter un dossier mémoire local.
4. Examinez les sources et l'aperçu, puis confirmez tout envoi à Hindsight.

L'app **n'inclut pas le serveur ni les modèles**. Pour en installer un, suivez
la [documentation officielle](https://hindsight.vectorize.io).
Les collecteurs locaux sont facultatifs et nécessitent leur propre configuration.
Les appels aux modèles peuvent être payants selon les réglages du serveur.

Les sources locales restent consultables sans serveur. Les suppressions et
les traitements sont confirmés dans l'app. Les données envoyées peuvent être
transmises par votre serveur à ses fournisseurs de modèles : consultez la
[confidentialité](PRIVACY.md) avant d'importer des données sensibles.

## Aide et mises à jour

- [Signaler un problème](https://github.com/paabL/hindsight-desktop/issues), sans
  joindre de conversations privées, de clés ou de journaux complets.
- [Signaler une faille de sécurité](SECURITY.md).
- Pour mettre à jour l'app téléchargée, installez la nouvelle version depuis
  les [releases](https://github.com/paabL/hindsight-desktop/releases).
  La reconstruction depuis les sources dans les réglages est destinée aux développeurs.

## English

An independent macOS desktop client for Hindsight. Browse local sources, search
memories and manage your server in a quiet, simple interface. Free software under
[MIT](LICENSE), with no official affiliation with Vectorize AI, Inc.

**Requires macOS 15 or newer.** Download the file for your Mac from
[Releases](https://github.com/paabL/hindsight-desktop/releases), open the DMG and
drag **Hindsight Desktop** into **Applications**. Only architectures explicitly
listed in the release are supported. No developer tools are needed to run it.

This early beta is **not notarized by Apple**. After trying to open it, macOS may
require **System Settings → Privacy & Security → Open Anyway**. Only approve a
verified download. [Apple's instructions](https://support.apple.com/102445).
Do not disable macOS security protections.

Select your language, then configure an existing Hindsight server in Settings
(default local address: `http://127.0.0.1:8888`) and choose a memory bank. Recent
features target API 1.2.0; availability depends on your server. Local source
browsing also works offline. Review the preview before approving an upload.

The server and models are **not included**. See the
[official setup documentation](https://hindsight.vectorize.io). Optional local
collectors require separate configuration. Your server's model providers may
charge fees and receive uploaded content; read [Privacy](PRIVACY.md).

Install future versions from Releases. Report ordinary bugs in
[Issues](https://github.com/paabL/hindsight-desktop/issues), and vulnerabilities
through [Security](SECURITY.md). Never post private conversations or credentials.

## Développer / Develop

Tauri 2 + React / TypeScript, avec un moteur Swift interne. Prérequis : macOS 15+,
Node.js 22.18+, Xcode 16+ / Swift 6 et Rust stable.

```sh
cd desktop
npm ci
npm run dev
```

```sh
# À la racine / At the repository root
swift test
cd desktop
npm run bridge:build
npm test
npm run build
npm run tauri:build -- --bundles app,dmg
```

Le bundle inclut le pont natif. [Guide technique](desktop/README.md),
[vérifications](docs/TESTING.md), [interface](docs/UI.md),
[notices des dépendances](THIRD_PARTY_NOTICES.md).
Les modèles API sont générés depuis `docs/openapi.json`.
