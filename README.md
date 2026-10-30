# garmindb-docker

Image Docker et CI/CD pour faire tourner [GarminDB](https://github.com/tcgoetz/GarminDB) **tel quel**
(code upstream, sans modification), avec une synchro quotidienne automatique. Le but est de garder une
sauvegarde locale complète des données Garmin Connect (bases SQLite et fichiers FIT).

Ce repo ne contient que de l'emballage : le sous-module GarminDB, un Dockerfile, trois petits scripts
(synchro, healthcheck, démarrage) et la CI.

## Fonctionnement

- [supercronic](https://github.com/aptible/supercronic) lance la synchro selon `SYNC_SCHEDULE`
  (par défaut chaque jour à 04:00, dans le fuseau `TZ`). Pas de synchro au démarrage du conteneur.
- La commande lancée est `garmindb_cli.py --all --download --import --analyze --latest`.
- Un verrou empêche deux synchros de tourner en même temps.
- Après chaque synchro réussie, l'heure est écrite dans `/root/HealthData/last_success`.
- Le conteneur passe en `unhealthy` si aucune synchro n'a réussi depuis `MAX_AGE_HOURS` heures
  (par exemple, jetons Garmin expirés).

## Variables d'environnement

| Variable        | Défaut      | Rôle                                               |
|-----------------|-------------|----------------------------------------------------|
| `TZ`            | UTC         | Fuseau horaire de la planification                 |
| `SYNC_SCHEDULE` | `0 4 * * *` | Expression cron de la synchro                      |
| `MAX_AGE_HOURS` | `36`        | Âge maximum de la dernière réussite avant `unhealthy` |

## Volumes

| Chemin conteneur   | Contenu                                                            |
|--------------------|--------------------------------------------------------------------|
| `/root/.GarminDb`  | `GarminConnectConfig.json` (identifiants, options) + jetons Garmin |
| `/root/HealthData` | bases SQLite, fichiers FIT, `last_success`                         |

Voir [`docker-compose.example.yml`](docker-compose.example.yml).

## Commandes utiles

```bash
docker compose exec garmindb sync-now          # lancer une synchro à la main
docker compose exec garmindb healthcheck.sh    # état de la dernière synchro
docker logs -f garmindb                        # logs des synchros
```

## Mise en place sur le serveur (reprise des données de garmin-bridge)

1. Copier les données existantes, sans toucher aux originaux (adapter les chemins à ceux du
   compose actuel) :
   ```bash
   mkdir -p garmindb-docker
   cp -a garmindb_conf garmindb-docker/conf
   cp -a garmindb_data garmindb-docker/data
   ```
2. Ajouter le service au compose, puis `docker compose up -d garmindb`.
3. `docker compose exec garmindb sync-now`, puis vérifier les logs, la date des bases dans
   `data/DBs/` et la présence de `last_success`.
4. Le lendemain, vérifier qu'une synchro a eu lieu vers 04:00 et que le conteneur est `healthy`.

Les anciens dossiers `garmindb_conf/` et `garmindb_data/` restent en place : les outils d'écriture
de garmin-bridge utilisent encore les jetons de `garmindb_conf/`.

## CI/CD

- Push sur `main` : tests des scripts, build, push de `garmindb-docker:latest` sur Docker Hub
  (l'ancienne image est retaguée `previous`), puis redéploiement via le webhook n8n.
- Pull request : tests des scripts et build de l'image, sans push.
- Dependabot ouvre chaque semaine une PR si GarminDB a publié une nouvelle version.

Secrets du repo : `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `N8N_WEBHOOK_ID`.

## Tests

```bash
bash tests/run.sh
```

Les scripts sont testés avec un faux `garmindb_cli.py` : aucun compte Garmin n'est nécessaire.
