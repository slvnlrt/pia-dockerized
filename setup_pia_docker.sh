#!/bin/bash
set -e # Quitte immédiatement si une commande échoue

PROJECT_DIR="pia-dockerized"
RUBY_VERSION_TARGET="3.3.0" # Version de Ruby cible
NODE_VERSION_TARGET="18"    # Version de Node.js pour le build frontend

# Commits spécifiques des dépôts PIA pour assurer la compatibilité
PIA_BACK_VERSION="ed560005ab885cf0b717416bfd0c4f95c5bfc268"
PIA_FRONT_VERSION="eda0f2631afbe2d2279f137a8ff2a8ad36fd7e4a"

# --- FONCTIONS UTILITAIRES ---
print_info() { echo -e "\nINFO: $1\n--------------------------------------------------"; }
print_success() { echo -e "\n✅ SUCCESS: $1\n--------------------------------------------------"; }
print_warning() { echo -e "\n⚠️ WARNING: $1\n--------------------------------------------------"; }
print_error() { echo -e "\n❌ ERROR: $1\n--------------------------------------------------" >&2; exit 1; }

# --- VÉRIFICATION DES DÉPENDANCES ---
command -v git >/dev/null 2>&1 || print_error "Git n'est pas installé. Veuillez l'installer."
command -v docker >/dev/null 2>&1 || print_error "Docker n'est pas installé. Veuillez l'installer."
DOCKER_COMPOSE_CMD="docker-compose"
if ! command -v docker-compose &> /dev/null; then
  if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
    print_info "Utilisation de 'docker compose' (v2)."
  else
    print_error "Docker Compose (v1 ou v2) n'est pas installé. Veuillez l'installer."
  fi
fi

# --- CRÉATION DE LA STRUCTURE DES DOSSIERS ---
print_info "Création de la structure des dossiers pour '$PROJECT_DIR'..."
if [ -d "$PROJECT_DIR" ]; then
    print_warning "Le dossier $PROJECT_DIR existe déjà. Suppression et recréation pour un état propre."
    rm -rf "$PROJECT_DIR"
fi
mkdir -p "$PROJECT_DIR/backend/lib/tasks"
mkdir -p "$PROJECT_DIR/frontend"
cd "$PROJECT_DIR" || print_error "Impossible de se déplacer dans $PROJECT_DIR"


# --- CRÉATION DES FICHIERS DE CONFIGURATION PRINCIPAUX ---
print_info "Création de .env.example..."
cat << 'EOF' > .env.example
# Fichier: .env.example

# --- PostgreSQL Settings ---
POSTGRES_USER=pia-user
POSTGRES_PASSWORD=CHANGEME_DATABASE_PASSWORD
POSTGRES_DB=pia_production_db
POSTGRES_PORT=5432

# --- PIA Backend Docker Environment Settings ---
# Générez ces clés avec : docker run --rm ruby:3.3.0-slim ruby -e "require 'securerandom'; puts SecureRandom.hex(64)"
SECRET_KEY_BASE=CHANGEME_PLEASE_GENERATE_A_SECRET_KEY_BASE
DEVISE_SECRET_KEY=CHANGEME_PLEASE_GENERATE_DEVISE_SECRET_KEY
DEVISE_PEPPER=CHANGEME_PLEASE_GENERATE_DEVISE_PEPPER
RAILS_MASTER_KEY= # Optionnel: Remplir si vous utilisez Rails credentials chiffrés pour SMTP

RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true
ENABLE_AUTHENTICATION=true
DEFAULT_LOCALE=fr

# --- Initial Admin User for PIA Backend ---
PIA_ADMIN_EMAIL=admin@example.com
PIA_ADMIN_PASSWORD=CHANGEME_PiaAdminPassword123! # Doit être complexe (min 12 chars, chiffres, symboles)

# --- SMTP Settings (Optionnel, requis pour l'envoi d'emails par PIA) ---
# Si ces variables ne sont pas définies, les emails ne seront pas envoyés et aucune erreur ne sera levée.
# SMTP_ADDRESS=your.smtp.server.com
# SMTP_PORT=587
# SMTP_DOMAIN=yourdomain.com
# SMTP_USER_NAME=your_smtp_username
# SMTP_PASSWORD=your_smtp_password
# SMTP_AUTHENTICATION=plain # Ex: plain, login, cram_md5
# SMTP_ENABLE_STARTTLS_AUTO=true
# EMAIL_FROM=pia@yourdomain.com

# --- PIA Frontend Settings (pour Nginx) ---
# NGINX_HTTP_PORT=80  # Optionnel: Décommentez pour changer le port HTTP exposé
# NGINX_HTTPS_PORT=443 # Optionnel: Décommentez pour changer le port HTTPS exposé
CERT_HOSTNAME=localhost
EOF

print_info "Création de .gitignore..."
cat << 'EOF' > .gitignore
.env
backend/pia-back/
frontend/pia/
node_modules/
vendor/bundle/
*.log
tmp/
.vscode/
.idea/
*.DS_Store
*.swp
*~
EOF

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
      RAILS_MASTER_KEY: ${RAILS_MASTER_KEY}
      RAILS_LOG_TO_STDOUT: ${RAILS_LOG_TO_STDOUT}
      RAILS_SERVE_STATIC_FILES: ${RAILS_SERVE_STATIC_FILES}
      DATABASE_URL: "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:${POSTGRES_PORT}/${POSTGRES_DB}"
      DEVISE_SECRET_KEY: ${DEVISE_SECRET_KEY}
      DEVISE_PEPPER: ${DEVISE_PEPPER}
      ENABLE_AUTHENTICATION: ${ENABLE_AUTHENTICATION}
      DEFAULT_LOCALE: ${DEFAULT_LOCALE}
      PIA_ADMIN_EMAIL: ${PIA_ADMIN_EMAIL}
      PIA_ADMIN_PASSWORD: ${PIA_ADMIN_PASSWORD}
      SMTP_ADDRESS: ${SMTP_ADDRESS}
      SMTP_PORT: ${SMTP_PORT}
      SMTP_DOMAIN: ${SMTP_DOMAIN}
      SMTP_USER_NAME: ${SMTP_USER_NAME}
      SMTP_PASSWORD: ${SMTP_PASSWORD}
      SMTP_AUTHENTICATION: ${SMTP_AUTHENTICATION}
      SMTP_ENABLE_STARTTLS_AUTO: ${SMTP_ENABLE_STARTTLS_AUTO}
      EMAIL_FROM: ${EMAIL_FROM}
    networks:
      - pia_network

  pia-frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: pia_frontend_web
    restart: unless-stopped
    ports:
      - "${NGINX_HTTP_PORT:-80}:80"
      - "${NGINX_HTTPS_PORT:-443}:443"
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
PIA_BACK_REPO_DIR="backend/pia-back"

# backend/Dockerfile
cat << EOF > backend/Dockerfile
FROM ruby:${RUBY_VERSION_TARGET}-slim

ENV LANG=C.UTF-8
ENV RAILS_ENV=\${RAILS_ENV:-production}
ENV APP_HOME=/usr/src/app/pia-back
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

RUN mkdir -p lib/tasks
COPY lib/tasks/pia_setup.rake lib/tasks/pia_setup.rake

RUN cp config/database.example.yml config/database.yml

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

EXPOSE 8080

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "8080"]
EOF

# backend/lib/tasks/pia_setup.rake
print_info "Création de la tâche Rake backend/lib/tasks/pia_setup.rake..."
cat << 'EOF' > backend/lib/tasks/pia_setup.rake
namespace :pia do
  desc "Setup PIA Doorkeeper application and initial admin user if they don't exist"
  task setup_auth: :environment do
    if ENV['RAILS_ENV'] == 'production' || ENV['RAILS_ENV'] == 'development'
      puts "[PIA Auth Setup] Starting setup for #{ENV['RAILS_ENV']} environment..."
      app_name = "PIA"
      redirect_uri_value = "urn:ietf:wg:oauth:2.0:oob"
      scopes_value = "read write"
      existing_app = Doorkeeper::Application.find_by(name: app_name)
      if existing_app
        puts "[PIA Auth Setup] Doorkeeper application '#{app_name}' already exists."
        puts "[PIA Auth Setup]   Client ID (uid): #{existing_app.uid}"
        puts "[PIA Auth Setup]   Client Secret: #{existing_app.secret}"
      else
        puts "[PIA Auth Setup] Creating Doorkeeper application '#{app_name}'..."
        application = Doorkeeper::Application.new(name: app_name, redirect_uri: redirect_uri_value, scopes: scopes_value)
        if application.save
          puts "[PIA Auth Setup] Doorkeeper application '#{app_name}' created successfully."
          puts "[PIA Auth Setup]   Client ID (uid): #{application.uid}"
          puts "[PIA Auth Setup]   Client Secret: #{application.secret}"
          puts "[PIA Auth Setup]   => NOTEZ BIEN CES INFORMATIONS POUR CONFIGURER LE FRONTEND PIA <="
        else
          puts "[PIA Auth Setup] ERROR: Failed to create Doorkeeper application: #{application.errors.full_messages.join(', ')}"
        end
      end
      admin_email = ENV['PIA_ADMIN_EMAIL'] || 'admin@example.com'
      admin_password = ENV['PIA_ADMIN_PASSWORD']
      if admin_password.blank? || admin_password.length < 12
         puts "[PIA Auth Setup] ERROR: PIA_ADMIN_PASSWORD is not set or too short (min 12 chars). Admin user not created."
      elsif User.exists?(email: admin_email)
        puts "[PIA Auth Setup] Admin user '#{admin_email}' already exists."
      else
        puts "[PIA Auth Setup] Creating admin user '#{admin_email}'..."
        user = User.new(email: admin_email, password: admin_password, password_confirmation: admin_password,
                        is_technical_admin: true, is_functional_admin: true, is_user: true)
        user.confirm if user.respond_to?(:confirm) && !user.confirmed?
        user.unlock_access! if user.respond_to?(:unlock_access!) && user.access_locked?
        if user.save
          puts "[PIA Auth Setup] Admin user '#{admin_email}' created successfully."
        else
          puts "[PIA Auth Setup] ERROR: Failed to create admin user '#{admin_email}': #{user.errors.full_messages.join(', ')}"
        end
      end
      puts "[PIA Auth Setup] Setup finished."
    else
      puts "[PIA Auth Setup] Skipping setup for environment: #{ENV['RAILS_ENV']}"
    end
  end
end
EOF

# backend/entrypoint.sh
cat << 'EOF' > backend/entrypoint.sh
#!/bin/bash
set -e
echo "Attente de PostgreSQL sur $POSTGRES_HOST:$POSTGRES_PORT..."
until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -q -U "$POSTGRES_USER"; do
  echo "PostgreSQL n'est pas encore prêt. Nouvelle tentative dans 2 secondes..."
  sleep 2
done
echo "PostgreSQL est prêt."
echo "Préparation de la base de données (création si besoin, migrations, seeds)..."
bundle exec rake db:prepare
echo "Configuration initiale de l'authentification PIA (Doorkeeper app, admin user)..."
bundle exec rake pia:setup_auth
echo "Lancement du serveur Rails..."
exec "$@"
EOF
chmod +x backend/entrypoint.sh

# Clonage et modification de pia-back
print_info "Clonage de LINCnil/pia-back (version: $PIA_BACK_VERSION)..."
rm -rf "$PIA_BACK_REPO_DIR"
git clone https://github.com/LINCnil/pia-back.git "$PIA_BACK_REPO_DIR" || print_error "Échec du clonage de pia-back"
(cd "$PIA_BACK_REPO_DIR" && git checkout "$PIA_BACK_VERSION") || print_error "Échec du checkout du commit $PIA_BACK_VERSION pour pia-back"

print_info "Modification de $PIA_BACK_REPO_DIR/.ruby-version..."
echo "${RUBY_VERSION_TARGET}" > "$PIA_BACK_REPO_DIR/.ruby-version"

print_info "Configuration de $PIA_BACK_REPO_DIR/config/database.example.yml..."
if [ ! -f "$PIA_BACK_REPO_DIR/config/database.example.yml" ]; then
    echo "production:" > "$PIA_BACK_REPO_DIR/config/database.example.yml"
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

if [ -f "$PIA_BACK_REPO_DIR/.env-example" ]; then
    cp "$PIA_BACK_REPO_DIR/.env-example" "$PIA_BACK_REPO_DIR/.env"
else
    print_warning "$PIA_BACK_REPO_DIR/.env-example non trouvé. Création d'un .env vide pour pia-back."
    touch "$PIA_BACK_REPO_DIR/.env"
fi

PROD_ENV_RB="$PIA_BACK_REPO_DIR/config/environments/production.rb"
if [ -f "$PROD_ENV_RB" ]; then
    print_info "Modification de $PROD_ENV_RB pour la gestion des emails..."
    # Assurer que le bloc de configuration Rails existe
    if ! grep -q "Rails.application.configure do" "$PROD_ENV_RB"; then
        echo -e "\nRails.application.configure do\nend" >> "$PROD_ENV_RB"
    fi
    
    # Configuration par défaut : pas d'erreur SMTP, mode test
    if ! grep -q "config.action_mailer.delivery_method = :test" "$PROD_ENV_RB"; then
        sed -i "/Rails.application.configure do/a\
\  config.action_mailer.delivery_method = :test" "$PROD_ENV_RB"
    fi
    if ! grep -q "config.action_mailer.raise_delivery_errors = false" "$PROD_ENV_RB"; then
        sed -i "/Rails.application.configure do/a\
\  config.action_mailer.raise_delivery_errors = false" "$PROD_ENV_RB"
    fi

    # Configuration SMTP conditionnelle si ENV['SMTP_ADDRESS'] est présent
    # On s'assure de ne pas l'ajouter si elle existe déjà pour éviter les doublons
    SMTP_CONFIG_BLOCK_IDENTIFIER="# START PIA DOCKER SMTP CONFIG"
    if ! grep -q "$SMTP_CONFIG_BLOCK_IDENTIFIER" "$PROD_ENV_RB"; then
        # Utiliser awk pour insérer le bloc à l'intérieur de Rails.application.configure do ... end
        # Ceci est plus robuste que de multiples sed -i /a\
        awk '
        /Rails.application.configure do/ {
            print;
            print "  # START PIA DOCKER SMTP CONFIG";
            print "  # Configuration SMTP conditionnelle";
            print "  if ENV[\"SMTP_ADDRESS\"].present?";
            print "    config.action_mailer.delivery_method = :smtp";
            print "    config.action_mailer.perform_deliveries = true";
            print "    config.action_mailer.raise_delivery_errors = true # Ou false selon la préférence";
            print "    config.action_mailer.default_url_options = { host: ENV[\"CERT_HOSTNAME\"] || \"localhost\", protocol: \"https\" }";
            print "    config.action_mailer.smtp_settings = {";
            print "      address:              ENV[\"SMTP_ADDRESS\"],";
            print "      port:                 (ENV[\"SMTP_PORT\"] || 587).to_i,";
            print "      domain:               ENV[\"SMTP_DOMAIN\"],";
            print "      user_name:            ENV[\"SMTP_USER_NAME\"],";
            print "      password:             ENV[\"SMTP_PASSWORD\"],";
            print "      authentication:       (ENV[\"SMTP_AUTHENTICATION\"]&.to_sym if ENV[\"SMTP_AUTHENTICATION\"].present?),";
            print "      enable_starttls_auto: ENV[\"SMTP_ENABLE_STARTTLS_AUTO\"] == \"true\"";
            print "    }";
            print "    if ENV[\"EMAIL_FROM\"].present?";
            print "      config.action_mailer.default_options = { from: ENV[\"EMAIL_FROM\"] }";
            print "    end";
            print "  else";
            print "    # Fallback si SMTP_ADDRESS n est pas défini";
            print "    config.action_mailer.delivery_method = :test";
            print "    config.action_mailer.raise_delivery_errors = false";
            print "  end";
            print "  # END PIA DOCKER SMTP CONFIG";
            next;
        }
        { print }
        ' "$PROD_ENV_RB" > "${PROD_ENV_RB}.tmp" && mv "${PROD_ENV_RB}.tmp" "$PROD_ENV_RB"
    fi
else
    print_warning "$PROD_ENV_RB non trouvé. Configuration SMTP non modifiée."
fi


# --- CONFIGURATION DU FRONTEND ---
print_info "Configuration du frontend..."
PIA_FRONT_REPO_DIR="frontend/pia"

# frontend/Dockerfile
cat << EOF > frontend/Dockerfile
FROM node:${NODE_VERSION_TARGET}-alpine AS builder
WORKDIR /usr/src/app
COPY pia/package*.json ./
RUN npm install --legacy-peer-deps
COPY pia/ .
RUN cp src/environments/environment.prod.ts.example src/environments/environment.prod.ts
RUN sed -i "s|apiUrl: '%%API_URL%%'|apiUrl: ''|" src/environments/environment.prod.ts
RUN npm run build -- --configuration production --base-href /

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

# frontend/nginx.conf (version simplifiée et validée)
cat << 'EOF' > frontend/nginx.conf
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
        try_files $uri $uri/ @backend_proxy;
    }

    location @backend_proxy {
        proxy_pass http://pia-backend:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
    }

    gzip on; gzip_vary on; gzip_proxied any; gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
}
EOF

# frontend/entrypoint.sh
cat << 'EOF' > frontend/entrypoint.sh
#!/bin/sh
set -e
CERT_DIR="/etc/nginx/certs"; KEY_FILE="${CERT_DIR}/nginx.key"; CERT_FILE="${CERT_DIR}/nginx.crt"
DAYS_VALID="365"; ACTUAL_HOSTNAME="${CERT_HOSTNAME:-localhost}"
echo "Configuration de Nginx pour server_name: ${ACTUAL_HOSTNAME}"
sed -i "s/__CERT_HOSTNAME__/${ACTUAL_HOSTNAME}/g" /etc/nginx/conf.d/nginx.conf
if [ ! -f "$KEY_FILE" ] || [ ! -f "$CERT_FILE" ]; then
  echo "Génération SSL pour ${ACTUAL_HOSTNAME}..."; mkdir -p "$CERT_DIR"
  openssl req -x509 -nodes -newkey rsa:2048 -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -days "$DAYS_VALID" -subj "/CN=${ACTUAL_HOSTNAME}" -addext "subjectAltName = DNS:${ACTUAL_HOSTNAME}"
  echo "Certificat SSL généré."; else echo "Certificat SSL existant."; fi
exec "$@"
EOF
chmod +x frontend/entrypoint.sh

# Clonage et modification de pia (frontend)
print_info "Clonage de LINCnil/pia (frontend) (version: $PIA_FRONT_VERSION)..."
rm -rf "$PIA_FRONT_REPO_DIR"
git clone https://github.com/LINCnil/pia.git "$PIA_FRONT_REPO_DIR" || print_error "Échec du clonage de pia (frontend)"
(cd "$PIA_FRONT_REPO_DIR" && git checkout "$PIA_FRONT_VERSION") || print_error "Échec du checkout du commit $PIA_FRONT_VERSION pour pia (frontend)"

print_info "Configuration de $PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example..."
if [ ! -f "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example" ]; then
    if [ -f "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts" ]; then
        cp "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts" "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example"
    else
        mkdir -p "$PIA_FRONT_REPO_DIR/src/environments"
        echo "export const environment = { production: true, apiUrl: '', name: 'PIA' };" > "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example"
    fi
fi
cat << 'EOENV' > "$PIA_FRONT_REPO_DIR/src/environments/environment.prod.ts.example"
import packageJson from '../../package.json';
export const environment = {
  name: 'production',
  production: true,
  version: packageJson.version,
  apiUrl: '' // Modifié pour être une chaîne vide
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
echo "   nano .env  # (Remplissez TOUS les placeholders CHANGEME_*)."
echo "                # (Générez SECRET_KEY_BASE, DEVISE_SECRET_KEY, DEVISE_PEPPER avec"
echo "                #  'docker run --rm ruby:${RUBY_VERSION_TARGET}-slim ruby -e \"require \\'securerandom\\'; puts SecureRandom.hex(64)\" ')"
echo "                # (Choisissez un PIA_ADMIN_PASSWORD complexe pour l'utilisateur admin initial)"
echo "                # (Optionnel: configurez les variables SMTP_* et EMAIL_FROM si vous voulez activer les emails et que les utilisateurs reçoivent les liens d'activation)"
echo "3. Construisez les images Docker :"
echo "   sudo $DOCKER_COMPOSE_CMD build"
echo "4. Démarrez les conteneurs :"
echo "   sudo $DOCKER_COMPOSE_CMD up -d"
echo "5. Vérifiez les logs du backend pour le Client ID et Secret de Doorkeeper, et le statut de création de l'admin:"
echo "   sudo $DOCKER_COMPOSE_CMD logs -f pia-backend"
echo "6. Accédez à l'application PIA Frontend : https://localhost (ou votre CERT_HOSTNAME)"
echo "7. Allez dans les paramètres du frontend et entrez le Client ID et le Client Secret affichés dans les logs du backend."
echo "8. Connectez-vous avec l'email et le mot de passe de l'admin initial."
echo "9. Pour les utilisateurs créés via l'interface (si SMTP n'est PAS configuré dans .env) :"
echo "   Ils seront créés mais VERROUILLÉS. L'application ne plantera plus (erreur 500) grâce à la config :test pour ActionMailer."
echo "   Pour les activer et définir leur mot de passe, connectez-vous à la console Rails du backend :"
echo "   sudo $DOCKER_COMPOSE_CMD exec pia-backend bin/rails c"
echo "   Puis : "
echo "   > u = User.find_by(email: 'email_du_nouvel_utilisateur@example.com')"
echo "   > u.password = 'NouveauMotDePasseComplexe123!'; u.password_confirmation = 'NouveauMotDePasseComplexe123!'"
echo "   > u.unlock_access!"
echo "   > u.save"
echo "   > exit"
echo "   L'utilisateur pourra alors se connecter avec le nouveau mot de passe."
cat << 'EOPASS'
   Attention - Exigences du mot de passe:
     - Longueur minimale : Au moins 12 caractères
     - Chiffre : Doit contenir au moins un chiffre (0-9)
     - Signe de ponctuation : Doit contenir au moins un caractère spécial
       (par exemple, !, @, #, $, %, ^, &, *, (, ), -, _, +, =, etc.)
     - Lettre majuscule : Doit contenir au moins une lettre majuscule (A-Z)
EOPASS
echo "Pour supprimer le volume de données PostgreSQL et recommencer à zéro :"
echo "docker volume rm pia-dockerized_postgres_data"