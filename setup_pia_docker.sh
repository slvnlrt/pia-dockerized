#!/bin/bash
set -e # Quitte immédiatement si une commande échoue
# set -x # Décommenter pour afficher chaque commande exécutée

PROJECT_DIR="pia-dockerized"
RUBY_VERSION_TARGET="3.3.0"
NODE_VERSION_TARGET="18"

# --- Versions des dépôts PIA (FIXÉES AUX COMMITS ACTUELS QUI FONCTIONNENT) ---
PIA_BACK_VERSION="ed560005ab885cf0b717416bfd0c4f95c5bfc268"
PIA_FRONT_VERSION="eda0f2631afbe2d2279f137a8ff2a8ad36fd7e4a"


# --- FONCTIONS UTILITAIRES ---
print_info() {
  echo ""
  echo "INFO: $1"
  echo "--------------------------------------------------"
}

print_success() {
  echo ""
  echo "✅ SUCCESS: $1"
  echo "--------------------------------------------------"
}

print_warning() {
  echo ""
  echo "⚠️ WARNING: $1"
  echo "--------------------------------------------------"
}

print_error() {
  echo ""
  echo "❌ ERROR: $1"
  echo "--------------------------------------------------" >&2
  exit 1
}

# --- VÉRIFICATION DES DÉPENDANCES ---
command -v git >/dev/null 2>&1 || { print_error "Git n'est pas installé. Veuillez l'installer."; }
command -v docker >/dev/null 2>&1 || { print_error "Docker n'est pas installé. Veuillez l'installer."; }
command -v docker-compose >/dev/null 2>&1 || { print_error "Docker Compose n'est pas installé. Veuillez l'installer."; }


# --- CRÉATION DE LA STRUCTURE DES DOSSIERS ---
print_info "Création de la structure des dossiers pour '$PROJECT_DIR'..."
# Supprimer le dossier existant pour assurer un état propre si on relance le script
if [ -d "$PROJECT_DIR" ]; then
    print_warning "Le dossier $PROJECT_DIR existe déjà. Il va être supprimé et recréé."
    rm -rf "$PROJECT_DIR"
fi
mkdir -p "$PROJECT_DIR/backend"
mkdir -p "$PROJECT_DIR/frontend"
cd "$PROJECT_DIR" || { print_error "Impossible de se déplacer dans le dossier $PROJECT_DIR"; }


# --- CRÉATION DES FICHIERS DE CONFIGURATION PRINCIPAUX ---

# .env.example
print_info "Création de .env.example..."
cat << 'EOF' > .env.example
# Fichier: .env.example

# --- PostgreSQL Settings ---
POSTGRES_USER=pia-user
POSTGRES_PASSWORD=CHANGEME_DATABASE_PASSWORD
POSTGRES_DB=pia_production_db
POSTGRES_PORT=5432

# --- PIA Backend Settings ---
# Générez une clé avec: ruby -e "require 'securerandom'; puts SecureRandom.hex(64)"
# Ou via Docker: docker run --rm ruby:3.3.0-slim ruby -e "require 'securerandom'; puts SecureRandom.hex(64)"
SECRET_KEY_BASE=CHANGEME_PLEASE_GENERATE_A_SECRET_KEY
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

# --- PIA Frontend Settings ---
API_BASE_URL=/api/v1

# --- SSL Certificate Settings ---
CERT_HOSTNAME=localhost
EOF

# .gitignore
print_info "Création de .gitignore..."
cat << 'EOF' > .gitignore
# Fichier: .gitignore

# Secrets
.env

# Code source des applications clonées (on les clone pour le build)
# Commenté car nous voulons que le script clone une version spécifique
backend/pia-back/
frontend/pia/

# Dépendances locales si on développait en dehors de Docker
node_modules/
vendor/bundle/

# Fichiers temporaires et de log
*.log
tmp/

# Fichiers IDE
.vscode/
.idea/
*.DS_Store
*.swp
*~
EOF

# docker-compose.yml
print_info "Création de docker-compose.yml..."
cat << 'EOF' > docker-compose.yml
version: '3.8'

services:
  db:
    image: postgres:13-alpine
    container_name: pia_postgres_db
    restart: unless-stopped
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    networks:
      - pia_network

  pia-backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: pia_backend_app
    restart: unless-stopped
    depends_on:
      - db
    volumes:
      - bundle_cache:/gems
    environment:
      RAILS_ENV: ${RAILS_ENV}
      POSTGRES_HOST: db
      POSTGRES_PORT: ${POSTGRES_PORT}
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      RAILS_LOG_TO_STDOUT: ${RAILS_LOG_TO_STDOUT}
      RAILS_SERVE_STATIC_FILES: ${RAILS_SERVE_STATIC_FILES}
      DATABASE_URL: "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:${POSTGRES_PORT}/${POSTGRES_DB}"
    networks:
      - pia_network

  pia-frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      args:
        API_BASE_URL: ${API_BASE_URL}
    container_name: pia_frontend_web
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - pia-backend
    volumes:
      - nginx_certs:/etc/nginx/certs
    environment:
      CERT_HOSTNAME: ${CERT_HOSTNAME}
    networks:
      - pia_network

volumes:
  postgres_data:
  bundle_cache:
  nginx_certs:

networks:
  pia_network:
    driver: bridge
EOF


# --- CONFIGURATION DU BACKEND ---
print_info "Configuration du backend..."

# backend/Dockerfile
cat << EOF > backend/Dockerfile
# Fichier: pia-dockerized/backend/Dockerfile
FROM ruby:${RUBY_VERSION_TARGET}-slim

ENV LANG=C.UTF-8
ENV RAILS_ENV=\${RAILS_ENV:-production}
ENV APP_HOME=/usr/src/app
ENV BUNDLE_PATH=/gems
ENV BUNDLE_WITHOUT="development:test"

RUN gem update --system

RUN apt-get update -qq && apt-get install -y --no-install-recommends \\
    build-essential \\
    libpq-dev \\
    nodejs \\
    yarn \\
    postgresql-client \\
    zlib1g-dev \\
    libxml2-dev \\
    && rm -rf /var/lib/apt/lists/*

WORKDIR \$APP_HOME

RUN gem install bundler -v 2.5.10 --no-document

COPY pia-back/Gemfile pia-back/Gemfile.lock pia-back/.ruby-version ./

RUN bundle install --jobs \$(nproc) --retry 3

COPY pia-back/ .

RUN cp config/database.example.yml config/database.yml

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

EXPOSE 8080

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "8080"]
EOF

# backend/entrypoint.sh
cat << 'EOF' > backend/entrypoint.sh
#!/bin/bash
set -e

if [ -z "$SECRET_KEY_BASE" ]; then
  echo "ERREUR: La variable d'environnement SECRET_KEY_BASE n'est pas définie."
  exit 1
fi

echo "Attente de PostgreSQL sur $POSTGRES_HOST:$POSTGRES_PORT..."
until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -q -U "$POSTGRES_USER"; do
  echo "PostgreSQL n'est pas encore prêt. Nouvelle tentative dans 2 secondes..."
  sleep 2
done
echo "PostgreSQL est prêt."

echo "Préparation de la base de données (création si besoin, migrations, seeds)..."
bundle exec rake db:prepare

echo "Lancement du serveur Rails..."
exec "$@"
EOF
chmod +x backend/entrypoint.sh


# Clonage et modification de pia-back
print_info "Clonage de LINCnil/pia-back..."
PIA_BACK_REPO_DIR="backend/pia-back"
# On supprime le dossier s'il existe pour cloner la version exacte
rm -rf "$PIA_BACK_REPO_DIR"
git clone https://github.com/LINCnil/pia-back.git "$PIA_BACK_REPO_DIR" || print_error "Échec du clonage de pia-back"

if [ -n "$PIA_BACK_VERSION" ]; then
  print_info "Passage au commit $PIA_BACK_VERSION pour pia-back..."
  (cd "$PIA_BACK_REPO_DIR" && git checkout "$PIA_BACK_VERSION") || print_error "Échec du checkout du commit $PIA_BACK_VERSION pour pia-back"
else
  print_warning "Aucune version spécifique (commit/tag) n'a été définie pour pia-back. Utilisation de la branche par défaut."
fi


print_info "Modification de $PIA_BACK_REPO_DIR/.ruby-version..."
echo "${RUBY_VERSION_TARGET}" > "$PIA_BACK_REPO_DIR/.ruby-version"

print_info "Configuration de $PIA_BACK_REPO_DIR/config/database.example.yml..."
# S'assurer que le fichier example existe après le checkout
if [ ! -f "$PIA_BACK_REPO_DIR/config/database.example.yml" ]; then
    print_warning "$PIA_BACK_REPO_DIR/config/database.example.yml non trouvé après checkout. Création d'un fichier de base."
    cat << 'EODBE' > "$PIA_BACK_REPO_DIR/config/database.example.yml"
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 5
  template: template0

development:
  <<: *default
  database: pia_development

test:
  <<: *default
  database: pia_test

production:
  <<: *default
  database: pia_production
EODBE
fi

cat << 'EODB' > "$PIA_BACK_REPO_DIR/config/database.example.yml"
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV['POSTGRES_HOST'] %>
  port: <%= ENV['POSTGRES_PORT'] %>
  username: <%= ENV['POSTGRES_USER'] %>
  password: <%= ENV['POSTGRES_PASSWORD'] %>
  template: template0

development:
  <<: *default
  database: <%= ENV['POSTGRES_DB'] %>_dev

test:
  <<: *default
  database: <%= ENV['POSTGRES_DB'] %>_test

production:
  <<: *default
  database: <%= ENV['POSTGRES_DB'] %>
EODB


# --- CONFIGURATION DU FRONTEND ---
print_info "Configuration du frontend..."

# frontend/Dockerfile
cat << EOF > frontend/Dockerfile
# Fichier: pia-dockerized/frontend/Dockerfile

# --- Étape 1: Build de l'application Angular ---
FROM node:${NODE_VERSION_TARGET}-alpine AS builder

WORKDIR /usr/src/app

COPY pia/package*.json ./
RUN npm install --legacy-peer-deps

COPY pia/ .

RUN cp src/environments/environment.prod.ts.example src/environments/environment.prod.ts
ARG API_BASE_URL
RUN sed -i "s|%%API_URL%%|\${API_BASE_URL}|g" src/environments/environment.prod.ts

RUN npm run build -- --configuration production --base-href /

# --- Étape 2: Servir avec Nginx ---
FROM nginx:1.25-alpine

RUN apk add --no-cache openssl

RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/nginx.conf

COPY --from=builder /usr/src/app/dist/pia-angular/browser /usr/share/nginx/html

COPY entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

RUN mkdir -p /etc/nginx/certs

EXPOSE 80
EXPOSE 443

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
EOF

# frontend/nginx.conf
cat << 'EOF' > frontend/nginx.conf
# Fichier: pia-dockerized/frontend/nginx.conf
server {
    listen 80;
    server_name __CERT_HOSTNAME__;
    location / {
        return 301 https://$host$request_uri;
    }
}
server {
    listen 443 ssl http2;
    server_name __CERT_HOSTNAME__;
    ssl_certificate /etc/nginx/certs/nginx.crt;
    ssl_certificate_key /etc/nginx/certs/nginx.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    root /usr/share/nginx/html;
    index index.html index.htm;
    location / {
        try_files $uri $uri/ /index.html;
    }
    location /api/v1/ {
        proxy_pass http://pia-backend:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_connect_timeout 60s;
        proxy_send_timeout   300s;
        proxy_read_timeout   300s;
        send_timeout         300s;
    }
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
}
EOF

# frontend/entrypoint.sh
cat << 'EOF' > frontend/entrypoint.sh
#!/bin/sh
set -e

CERT_DIR="/etc/nginx/certs"
KEY_FILE="${CERT_DIR}/nginx.key"
CERT_FILE="${CERT_DIR}/nginx.crt"
DAYS_VALID="365"
ACTUAL_HOSTNAME="${CERT_HOSTNAME:-localhost}"

echo "Configuration de Nginx pour server_name: ${ACTUAL_HOSTNAME}"
sed -i "s/__CERT_HOSTNAME__/${ACTUAL_HOSTNAME}/g" /etc/nginx/conf.d/nginx.conf

if [ ! -f "$KEY_FILE" ] || [ ! -f "$CERT_FILE" ]; then
  echo "Génération d'un nouveau certificat SSL auto-signé pour ${ACTUAL_HOSTNAME}..."
  mkdir -p "$CERT_DIR"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days "$DAYS_VALID" \
    -subj "/CN=${ACTUAL_HOSTNAME}" \
    -addext "subjectAltName = DNS:${ACTUAL_HOSTNAME}"
  echo "Certificat SSL auto-signé généré et sauvegardé dans ${CERT_DIR}."
else
  echo "Certificat SSL existant trouvé dans ${CERT_DIR}."
fi

exec "$@"
EOF
chmod +x frontend/entrypoint.sh


# Clonage et modification de pia (frontend)
print_info "Clonage de LINCnil/pia (frontend)..."
PIA_FRONT_REPO_DIR="frontend/pia"
# On supprime le dossier s'il existe pour cloner la version exacte
rm -rf "$PIA_FRONT_REPO_DIR"
git clone https://github.com/LINCnil/pia.git "$PIA_FRONT_REPO_DIR" || print_error "Échec du clonage de pia (frontend)"

if [ -n "$PIA_FRONT_VERSION" ]; then
  print_info "Passage au commit $PIA_FRONT_VERSION pour pia (frontend)..."
  (cd "$PIA_FRONT_REPO_DIR" && git checkout "$PIA_FRONT_VERSION") || print_error "Échec du checkout du commit $PIA_FRONT_VERSION pour pia (frontend)"
else
  print_warning "Aucune version spécifique (commit/tag) n'a été définie pour pia (frontend). Utilisation de la branche par défaut."
fi

print_info "Configuration de $PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example..."
# S'assurer que le fichier example existe après le checkout
if [ ! -f "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example" ]; then
    if [ -f "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts" ]; then
        cp "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts" "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example"
        print_warning "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example non trouvé. Copié depuis environment.prod.ts."
    else
        print_warning "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example non trouvé. Création d'un fichier de base."
        mkdir -p "$PIA_FRONT_REPO_DIR/src/environments"
        cat << 'EOENVEX' > "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example"
export const environment = {
  production: true,
  apiUrl: '%%API_URL%%',
  name: 'PIA'
};
EOENVEX
    fi
fi

cat << 'EOENV' > "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example"
import packageJson from '../../package.json';

export const environment = {
  name: 'production',
  production: true,
  version: packageJson.version,
  apiUrl: '%%API_URL%%'
};
EOENV

# --- FIN DE LA CONFIGURATION ---
print_success "Configuration complète terminée dans le dossier '$PROJECT_DIR'."
echo "Les versions suivantes ont été fixées pour les dépôts PIA :"
echo "  - pia-back: $PIA_BACK_VERSION"
echo "  - pia (frontend): $PIA_FRONT_VERSION"
echo ""
echo "PROCHAINES ÉTAPES :"
echo "1. Accédez au dossier : cd $PROJECT_DIR"
echo "2. Créez et configurez votre fichier .env :"
echo "   cp .env.example .env"
echo "   nano .env  # (Remplissez POSTGRES_PASSWORD et SECRET_KEY_BASE)."
echo "                # (Optionnel : modifiez CERT_HOSTNAME si vous voulez utiliser un autre nom d'hôte que 'localhost')"
echo "                # (Si vous changez CERT_HOSTNAME pour, par ex., 'pia.local', ajoutez '127.0.0.1 pia.local' à votre fichier /etc/hosts local)"
echo "3. Construisez les images Docker :"
echo "   sudo docker-compose build"
echo "4. Démarrez les conteneurs :"
echo "   sudo docker-compose up -d"
echo "5. Accédez à l'application : https://localhost (ou https://<votre_CERT_HOSTNAME_configuré>)"
echo ""
echo "Note: Si le clonage des dépôts pia-back ou pia échoue, assurez-vous d'avoir accès à Internet"
echo "et que les URL des dépôts GitHub sont correctes et accessibles."
