#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# 1. Install basic dependencies and Nginx
apt-get update -y
apt-get install -y git curl nginx

# 2. Configure Nginx Reverse Proxy
cat <<'EOF' > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name _;

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

# 3. Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# 4. Install PM2 globally
npm install -g pm2

RAW_ENV=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/APP_ENV_VARS")

echo "[DEBUG] RAW_ENV fetched from metadata: ${RAW_ENV}"

get_env_val() {
  local key="$1"
  echo "$RAW_ENV" | tr ',' '\n' | awk -F'=' -v k="$key" '$1 == k { print substr($0, length(k)+2) }'
}

GH_PAT="$(get_env_val "GH_PAT")"

# 5. Clone repository
mkdir -p /var/www
cd /var/www
if [ ! -d "school-timetable-management" ]; then
  git clone "https://oauth2:${GH_PAT}@github.com/daniel-modex/school-timetable-management.git"
fi

cd school-timetable-management

# 6. Fetch Metadata and populate .env file

cat <<EOT > .env
DATABASE_URL="$(get_env_val "SCHOOL_WEB_APP_DB_URL")"
AUTH_SECRET="$(get_env_val "SCHOOL_WEB_APP_AUTH_SECRET")"
EOT

# 7. Install dependencies, build, and start app
npm install
npm run build

pm2 start npm --name "timetable-app" -- run start
pm2 save
pm2 startup