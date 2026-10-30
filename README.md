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

## Mise en place

### Première installation

1. Créer `GarminConnectConfig.json` dans le volume de config à partir de
   [l'exemple de GarminDB](https://github.com/tcgoetz/GarminDB/blob/master/garmindb/GarminConnectConfig.json.example)
   (identifiants, dates de début, statistiques à télécharger).
2. `docker compose up -d garmindb`.
3. Faire la première connexion en mode interactif (Garmin peut demander un code MFA) et
   télécharger tout l'historique :
   ```bash
   docker compose exec -it garmindb garmindb_cli.py --all --download --import --analyze
   ```

### Reprise de données GarminDB existantes

1. Copier le dossier `~/.GarminDb` existant dans le volume de config et le dossier `HealthData`
   dans le volume de données (voir le tableau des volumes).
2. `docker compose up -d garmindb`.
3. Si les bases ont été créées par une autre version de GarminDB, la synchro échoue avec
   « version mismatch. Please rebuild ». Reconstruire les bases une fois :
   ```bash
   docker compose exec garmindb garmindb_cli.py --rebuild_db
   ```
   Les bases SQLite sont supprimées puis recréées à partir des fichiers FIT/JSON déjà téléchargés :
   rien n'est retéléchargé. Ça peut prendre un moment selon l'historique.

### Vérification

1. `docker compose exec garmindb sync-now`, puis vérifier la date des bases dans `data/DBs/` et
   la présence de `data/last_success`.
2. Le lendemain, vérifier qu'une synchro a eu lieu à l'heure prévue et que le conteneur est
   `healthy`.

Ce qui est lancé avec `docker compose exec` s'affiche dans le terminal, pas dans `docker logs`.
Le détail de la dernière exécution reste dans `data/garmindb.log`.

### Jetons Garmin

Si la connexion est refusée (conteneur `unhealthy`, « Failed to login! » dans les logs), il faut
refaire la connexion en mode interactif, car Garmin peut demander un code MFA :

```bash
docker compose exec -it garmindb garmindb_cli.py --all --download --latest
```

## CI/CD

- Push sur `main` : tests des scripts, build, push de `garmindb-docker:latest` sur Docker Hub
  (l'ancienne image est retaguée `previous`), puis redéploiement via le webhook n8n.
- Pull request : tests des scripts et build de l'image, sans push.
- Dependabot vérifie chaque semaine la branche `master` de GarminDB et ouvre une PR si elle a avancé.

Secrets du repo : `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `N8N_WEBHOOK_ID`.

## Tests

```bash
bash tests/run.sh
```

Les scripts sont testés avec un faux `garmindb_cli.py` : aucun compte Garmin n'est nécessaire.
