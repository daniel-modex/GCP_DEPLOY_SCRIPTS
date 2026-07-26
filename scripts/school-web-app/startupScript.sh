#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Install Node.js or Python depending on your stack
apt-get update -y
apt-get install -y git curl nginx


cat <<'EOF' > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name _; # Works for raw IP access, or replace with your domain name later

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

nginx -t
systemctl restart nginx
systemctl enable nginx

# Install Node.js (Example for Node app)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs pm2

# Clone repository
mkdir -p /var/www
cd /var/www
if [ ! -d "school-timetable-management" ]; then
  git clone https://github.com/daniel-modex/school-timetable-management.git
fi

cd school-timetable-management

# Create .env for Database Connection
RAW_ENV=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/APP_ENV_VARS")

get_env_val() {
  echo "$RAW_ENV" | tr ',' '\n' | grep "^$1=" | cut -d'=' -f2-
}

cat <<EOT > .env
DATABASE_URL=$(get_env_val "SCHOOL_WEB_APP_DB_URL")
AUTH_SECRET="$(get_env_val "SCHOOL_WEB_APP_AUTH_SECRET")"
EOT
HOSTNAME="0.0.0.0" PORT=3000
# Install and Start App
npm install
npm run build

sudo npm install -g pm2
pm2 start npm --name "timetable-app" -- run start
pm2 startup
pm2 save