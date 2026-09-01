# Resolume Arena Q-SYS Plugin

Plugin Q-SYS destiné au pilotage de Resolume Arena depuis un Core Q-SYS.

Le projet vise à proposer les fonctions principales de la connexion [Bitfocus Companion pour Resolume Arena](https://bitfocus.io/connections/resolume-arena), notamment le contrôle des clips, colonnes, layers, groupes, decks, paramètres et Dashboards, ainsi que leurs feedbacks en temps réel.

## État du projet

Le plugin est en cours de développement. La version actuelle fournit un framework
Q-SYS installable avec les pages `Composition` et `Setup`. Les premiers travaux ont validé :

- la connexion à l'API REST et au WebSocket de Resolume ;
- la réception et le réassemblage des grandes trames WebSocket dans Q-SYS ;
- l'affichage des thumbnails et des noms de clips ;
- les feedbacks de sélection en temps réel ;
- la mise à jour des clips lors d'un changement de deck ;
- la découverte et le pilotage des Links du Dashboard par identifiant de paramètre.

## Installation

Le fichier `.qplug` distribuable sera ajouté à la racine du dépôt dès la première version installable. Il pourra alors être copié dans le dossier des plugins utilisateur de Q-SYS Designer :

```text
%USERPROFILE%\Documents\QSC\Q-SYS Designer\Plugins
```

## Configuration de Resolume

Dans Resolume Arena, ouvrir les préférences du Webserver puis activer le serveur REST/WebSocket. Le port par défaut est `8080`.

Le Core Q-SYS doit pouvoir joindre l'adresse IP et le port du poste exécutant Resolume.

## Appearance

The design-time `Look and Feel` property offers two interface modes:

- `Resolume` uses the dark Resolume-inspired SVG controls;
- `Q-SYS` uses native Q-SYS buttons, suitable for copying into custom UCIs.

## Connection lifecycle

The plugin maintains one WebSocket connection to the configured Resolume host
and reconnects automatically after an interruption. The Setup page reports the
current connection state. A lightweight request to `/api/v1/product` detects a
disabled Resolume Webserver without polling composition or parameter state.

## Compilation

Les sources du plugin sont réparties entre les modules Lua situés à la racine. Le
fichier `plugin.lua` est le point d'entrée assemblé par `PLUGCC.exe`.

Dans Visual Studio Code, exécuter la tâche de build par défaut :

```text
Build and install ResolumeArena.qplug
```

La tâche propose l'incrément de `BuildVersion`, génère `ResolumeArena.qplug`, puis
le copie dans :

```text
%USERPROFILE%\Documents\QSC\Q-Sys Designer\Plugins\ResolumeArena
```

Le build peut également être lancé depuis PowerShell :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\plugincompile\build.ps1 -Increment development
```

## Publication

Le dépôt public contient :

- ce README ;
- les modules Lua placés à la racine et nécessaires à la compilation ;
- le fichier `.qplug` distribuable ;
- `.gitignore`.

Les scripts de test, captures, journaux, notes d'ingénierie inverse et autres fichiers sandbox restent locaux et ne sont pas publiés. Les fichiers Lua de test placés dans `tests/` restent donc exclus.

## Sources de référence

- [API REST Resolume Arena & Avenue](https://resolume.com/docs/restapi/)
- [API WebSocket Resolume](https://www.resolume.com/support/en/websocket-api)
- [Module Companion Resolume Arena](https://github.com/bitfocus/companion-module-resolume-arena)
