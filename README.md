# Resolume Arena Q-SYS Plugin

Plugin Q-SYS destiné au pilotage de Resolume Arena depuis un Core Q-SYS.

Le projet vise à proposer les fonctions principales de la connexion [Bitfocus Companion pour Resolume Arena](https://bitfocus.io/connections/resolume-arena), notamment le contrôle des clips, colonnes, layers, groupes, decks, paramètres et Dashboards, ainsi que leurs feedbacks en temps réel.

## État du projet

Le plugin est en cours de développement. Les premiers travaux ont validé :

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

## Publication

Le dépôt public contient uniquement :

- ce README ;
- le fichier `.qplug` distribuable ;
- `.gitignore`.

Les scripts de test, captures, journaux, notes d'ingénierie inverse et autres fichiers sandbox restent locaux et ne sont pas publiés.

## Sources de référence

- [API REST Resolume Arena & Avenue](https://resolume.com/docs/restapi/)
- [API WebSocket Resolume](https://www.resolume.com/support/en/websocket-api)
- [Module Companion Resolume Arena](https://github.com/bitfocus/companion-module-resolume-arena)

