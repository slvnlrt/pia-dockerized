# pia-dockerized
PIA x Docker

Ce projet fournit une configuration Docker (avec Docker Compose) pour installer et exécuter facilement l'outil PIA (Privacy Impact Assessment / Analyse d'Impact relative à la Protection des Données) développé par la CNIL.

Cette configuration utilise des versions spécifiques des composants PIA pour assurer la reproductibilité, qui sont automatiquement clonées et configurées par le script d'installation fourni.

## À Propos de l'outil PIA

L'outil PIA, proposé par la Commission Nationale de l'Informatique et des Libertés (CNIL), vise à aider les responsables de traitement à construire et à démontrer la conformité de leurs traitements de données au Règlement Général sur la Protection des Données (RGPD).

*   **Site officiel de l'outil PIA :** [https://www.cnil.fr/fr/outil-pia-telechargez-et-installez-le-logiciel-de-la-cnil](https://www.cnil.fr/fr/outil-pia-telechargez-et-installez-le-logiciel-de-la-cnil)
*   **Dépôt GitHub PIA Backend (`pia-back`) :** [https://github.com/LINCnil/pia-back](https://github.com/LINCnil/pia-back) (Licence MPL-2.0)
*   **Dépôt GitHub PIA Frontend (`pia`) :** [https://github.com/LINCnil/pia](https://github.com/LINCnil/pia) (Licence MPL-2.0)

**Remarque importante :** Cette configuration Docker utilise des versions spécifiques des dépôts PIA (indiquées ci-dessous) et des versions compatibles des environnements d'exécution (Ruby, Node.js), gérées par le script `setup_pia_docker.sh` et les `Dockerfile` inclus.

## Prérequis

*   [Git](https://git-scm.com/)
*   [Docker](https://www.docker.com/get-started)
*   [Docker Compose](https://docs.docker.com/compose/install/) (généralement inclus avec Docker Desktop, ou `docker compose` pour les versions plus récentes de Docker CLI).

## Installation et Lancement

1.  **Cloner ce dépôt :**
    ```bash
    git clone https://github.com/slvnlrt/pia-dockerized
    cd pia-dockerized
    ```

2.  **Exécuter le script de configuration :**
    Ce script va créer la structure de dossiers, les fichiers de configuration Docker, et cloner les versions spécifiques des dépôts `pia-back` et `pia`.
    ```bash
    chmod +x setup_pia_docker.sh
    ./setup_pia_docker.sh
    ```
    *Après l'exécution du script, assurez-vous d'être dans le dossier `pia-dockerized` qu'il a créé (par exemple, en exécutant `cd pia-dockerized` si vous avez lancé le script depuis le dossier parent).*

3.  **Configurer les variables d'environnement :**
    Accédez au dossier `pia-dockerized` (s'il a été créé par le script à l'étape précédente). Copiez le fichier d'exemple `.env.example` vers `.env` et modifiez-le.
    ```bash
    # Assurez-vous d'être dans le dossier pia-dockerized
    # cd pia-dockerized # Si nécessaire
    cp .env.example .env
    nano .env
    ```
    Vous **DEVEZ** impérativement :
    *   Remplacer `CHANGEME_DATABASE_PASSWORD` par un mot de passe robuste pour PostgreSQL.
    *   Remplacer `CHANGEME_PLEASE_GENERATE_A_SECRET_KEY` par une nouvelle `SECRET_KEY_BASE`. Vous pouvez utiliser la commande suggérée dans le fichier `.env` :
        `docker run --rm ruby:3.3.0-slim ruby -e "require 'securerandom'; puts SecureRandom.hex(64)"`
    *   (Optionnel) Modifier `CERT_HOSTNAME` si vous souhaitez utiliser un nom d'hôte autre que `localhost` pour le certificat SSL auto-signé et l'URL d'écoute de nginx. A modifier pour accéder a PIA depuis le réseau.

4.  **Construire les images Docker :**
    Cette étape peut prendre un certain temps la première fois...
    ```bash
    sudo docker-compose build
    ```

5.  **Démarrer les conteneurs :**
    ```bash
    sudo docker-compose up -d
    ```

6.  **Accéder à l'application :**
    Ouvrez votre navigateur et allez à `https://localhost` (ou `https://<votre_CERT_HOSTNAME_configuré>`).
    Vous devrez accepter l'avertissement de sécurité du navigateur (certificat SSL auto-signé).

## Structure du projet (générée par `setup_pia_docker.sh`)

```
pia-dockerized/
├── .env                     # (Vos secrets et configurations locales - NON VERSIONNÉ)
├── .env.example             # (Exemple de fichier .env)
├── .gitignore               # (Fichiers ignorés par Git)
├── docker-compose.yml       # (Définition des services Docker)
├── LICENSE                  # (Licence pour CE projet pia-dockerized - MIT par défaut)
├── setup_pia_docker.sh      # (Script d'installation complet)
│
├── backend/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── pia-back/            # (Cloné par le script, version spécifique)
│
└── frontend/
    ├── Dockerfile
    ├── nginx.conf
    ├── entrypoint.sh
    └── pia/                 # (Cloné par le script, version spécifique)
```

## Gestion des conteneurs

*   **Voir les logs :**
    ```bash
    sudo docker-compose logs -f               # Logs de tous les services
    sudo docker-compose logs -f pia-backend
    sudo docker-compose logs -f pia-frontend
    sudo docker-compose logs -f db
    ```

*   **Arrêter les conteneurs :**
    ```bash
    sudo docker-compose down
    ```

*   **Arrêter et supprimer les volumes (ATTENTION : supprime les données de la base et les certificats générés) :**
    ```bash
    sudo docker-compose down -v
    ```

## Versions des composants PIA utilisées

Le script `setup_pia_docker.sh` configure l'installation pour utiliser les commits spécifiques suivants, garantissant une version testée et fonctionnelle avec cette configuration Docker :

*   **PIA Backend (`pia-back`):** Commit `ed560005ab885cf0b717416bfd0c4f95c5bfc268`
*   **PIA Frontend (`pia`):** Commit `eda0f2631afbe2d2279f137a8ff2a8ad36fd7e4a`

## Dépannage

*   **Erreur de connexion à la base de données (lors du `docker-compose up`) :** Vérifiez vos variables d'environnement dans `.env` (surtout `POSTGRES_PASSWORD`). Assurez-vous que le service `db` a démarré correctement (`docker-compose logs -f db`).
*   **Problèmes de build (`docker-compose build`) :** Assurez-vous d'avoir une connexion Internet stable pour le téléchargement des images de base et des dépendances. Vérifiez les logs de `docker-compose build` pour des messages d'erreur spécifiques.

## Licence de cette configuration Docker

Les fichiers de configuration Docker (`Dockerfile`, `docker-compose.yml`, scripts `entrypoint.sh`, `setup_pia_docker.sh`, etc.) spécifiques à ce projet `pia-dockerized` sont distribués sous la **Licence MIT**. Voir le fichier `LICENSE` à la racine de ce dépôt pour plus de détails.

Les projets PIA (`pia-back` et `pia`), qui sont clonés par le script d'installation, sont développés par la CNIL et sont soumis à leurs propres licences (Mozilla Public License 2.0). Les fichiers de licence originaux sont conservés dans leurs répertoires respectifs après clonage.

## Contribution

Les suggestions d'amélioration pour cette configuration Docker sont les bienvenues via les Issues ou Pull Requests sur ce dépôt GitHub.
Pour des problèmes liés à l'outil PIA lui-même, veuillez vous référer aux dépôts officiels de la LINCnil listés ci-dessus.

