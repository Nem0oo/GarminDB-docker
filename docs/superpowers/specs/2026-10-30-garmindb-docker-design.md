# garmindb-docker : sauvegarde quotidienne Garmin via GarminDB

Date : 2026-10-30
Statut : en revue

## Contexte

`garmin-bridge` regroupe aujourd'hui trois rôles : synchro GarminDB, outils de lecture (REST + MCP)
et outils d'écriture/planning d'entraînements (via `garminconnect`). Depuis l'API officielle Garmin,
`garmin-mcp` couvre la lecture de façon plus fiable. Les outils de lecture du bridge sont désactivés
dans Claude.

On veut garder une copie locale complète des données Garmin (SQLite + FIT) au cas où l'accès officiel
change, devienne payant ou ferme. Cette spec couvre l'**étape 1** : sortir GarminDB dans un service
dédié. L'**étape 2** (nettoyage du bridge) aura sa propre spec.

## Objectif

Un repo `garmindb-docker` dont le seul but est de fournir une image Docker et sa CI/CD pour faire
tourner GarminDB **tel quel** (code source upstream, non modifié), avec une synchro quotidienne
automatique.

Critères de succès :
- Le service tourne via `docker compose` sur le serveur, à côté des autres.
- Les données existantes sont reprises : la première synchro ne retélécharge pas l'historique.
- Une synchro réussie a lieu chaque jour sans intervention.
- Un échec prolongé (ex. jetons Garmin expirés) se voit : conteneur `unhealthy`.
- Un push sur `main` reconstruit, publie et redéploie l'image comme pour `garmin-bridge`.

## Hors périmètre

- Aucune API ni MCP devant les données.
- Pas de copie hors du serveur (la sauvegarde du serveur lui-même couvre ce risque).
- Aucune modification de `garmin-bridge` (étape 2).
- Pas de workflow staging.

## Conception

### Repo

```
garmindb-docker/
├── GarminDB/                  # sous-module → https://github.com/tcgoetz/GarminDB (upstream)
├── Dockerfile
├── scripts/
│   ├── sync.sh                # une synchro (flock + last_success)
│   ├── healthcheck.sh
│   └── entrypoint.sh          # génère la crontab depuis SYNC_SCHEDULE
├── .github/
│   ├── workflows/build.yml
│   └── dependabot.yml
├── docker-compose.example.yml
└── README.md
```

- Sous-module : dépôt upstream `tcgoetz/GarminDB`, fixé sur le dernier tag de release au moment de
  l'implémentation. Aucun patch local. Les commits « metrics » du fork `nem0oo/GarminDB` ne sont pas
  repris (ils servaient uniquement aux outils de lecture du bridge).

### Image

Build en deux étapes, sur le modèle du Dockerfile actuel du bridge :

1. `python:3.12-slim` : `python -m build --wheel` sur le sous-module GarminDB.
2. `python:3.12-slim` : installe la wheel, `supercronic` (version fixée, somme SHA vérifiée), copie
   les scripts.

Pas de `libfaketime`, ni de FastAPI, matplotlib ou `garminconnect`.

### Synchro (`scripts/sync.sh`)

- Prend un verrou `flock -n /tmp/sync.lock` : si une synchro tourne déjà, on sort avec un message,
  sans erreur.
- Lance la commande GarminDB classique :
  `garmindb_cli.py --all --download --import --analyze --latest`
- Code retour 0 → écrit l'horodatage ISO dans `/root/HealthData/last_success`.
- Code retour ≠ 0 → propage le code d'erreur et ne touche pas `last_success`.
- Toute la sortie va sur stdout/stderr, donc dans `docker logs`.

Lancement manuel : `docker compose exec garmindb sync-now` (`sync-now` est un lien vers `sync.sh`
dans le `PATH`).

### Planification

- `scripts/entrypoint.sh` écrit l'heure de démarrage dans `/tmp/started_at`, génère la crontab à partir de
  `SYNC_SCHEDULE` (défaut `0 4 * * *`), puis `exec supercronic crontab`.
- Le fuseau horaire vient de `TZ` (variable compose habituelle).
- Pas de synchro au démarrage : la première a lieu à l'heure prévue, ou à la main avec `sync-now`.

### Surveillance (`scripts/healthcheck.sh`)

`HEALTHCHECK` Docker (intervalle 1 h) :
- `last_success` existe et a moins de `MAX_AGE_HOURS` (défaut 36) → sain.
- `last_success` absent : sain si le conteneur a démarré il y a moins de `MAX_AGE_HOURS`
  (lu dans `/tmp/started_at`), malsain sinon.
- Sinon → malsain.

### Configuration et données

| Chemin conteneur  | Contenu                                                                    |
|-------------------|----------------------------------------------------------------------------|
| `/root/.GarminDb` | `GarminConnectConfig.json` (identifiants, options) + jetons Garmin         |
| `/root/HealthData`| bases SQLite, fichiers FIT, `last_success`                                 |

Les identifiants restent dans `GarminConnectConfig.json`, comme aujourd'hui. Aucun secret dans l'image.

### Exemple compose

```yaml
services:
  garmindb:
    image: <dockerhub-user>/garmindb-docker:latest
    container_name: garmindb
    restart: unless-stopped
    environment:
      - TZ=Europe/Paris
      - SYNC_SCHEDULE=0 4 * * *
    volumes:
      - ./garmindb-docker/conf:/root/.GarminDb:rw
      - ./garmindb-docker/data:/root/HealthData:rw
```

### CI/CD

`.github/workflows/build.yml` : copie de `garmin-bridge/.github/workflows/build.yml` avec :
- checkout `submodules: recursive` ;
- image `garmindb-docker:latest`, l'ancienne `latest` étant retaguée `previous` ;
- cache GHA ;
- job de redéploiement via le webhook n8n.

Secrets à créer sur le repo : `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `N8N_WEBHOOK_ID`.

`.github/dependabot.yml` : écosystème `gitsubmodule`, répertoire `/`, vérification hebdomadaire.
Merger la PR met à jour GarminDB et déclenche build et redéploiement.

## Mise en place sur le serveur (manuelle)

Les données sont sur le serveur, à côté du compose de `garmin-bridge`.

1. Copier les données existantes, sans toucher aux originaux :
   ```bash
   mkdir -p garmindb-docker
   cp -a garmindb_conf garmindb-docker/conf
   cp -a garmindb_data garmindb-docker/data
   ```
   (adapter les chemins à ceux du compose actuel)
2. Ajouter le service au compose, puis `docker compose up -d garmindb`.
3. `docker compose exec garmindb sync-now`, puis vérifier les logs, la date des bases dans
   `data/DBs/` et la présence de `last_success`.
4. Le lendemain, vérifier qu'une synchro a eu lieu vers 04:00 et que le conteneur est `healthy`.

Les anciens dossiers `garmindb_conf/` et `garmindb_data/` restent en place.

## Contraintes pour l'étape 2 (nettoyage du bridge)

- Les outils d'écriture du bridge lisent les jetons dans `garmindb_conf/garmin_tokens.json`. Il ne
  faut **pas** supprimer ce dossier tant que le bridge n'a pas sa propre gestion de connexion
  (script de connexion `garminconnect`, fichier de jetons à lui).
- Ne pas déclencher la synchro du bridge une fois `garmindb` en service. Les deux copies sont
  indépendantes, mais c'est inutile.
- Avant suppression, poser un tag sur `garmin-bridge` pour garder les outils de lecture récupérables.

## Tests

- `docker build` réussit en local et en CI.
- En local, avec des volumes vides :
  - le conteneur démarre, et supercronic affiche la planification dans les logs ;
  - `sync-now` est appelable (il échoue faute de config, et `last_success` n'est pas écrit) ;
  - deux `sync-now` simultanés : le second sort immédiatement à cause du verrou ;
  - healthcheck : sain au démarrage sans `last_success` ; malsain avec un `last_success` vieux de
    plus de 36 h ; sain avec un `last_success` récent.
- Sur le serveur : étapes 3 et 4 de la mise en place.
