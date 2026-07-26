#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# 1. Install dependencies, Nginx, and jq
apt-get update -y
apt-get install -y git curl nginx jq

# 2. Configure Nginx
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

# 5. Extract JSON Secrets from Metadata and export as Environment Variables
RAW_SECRETS_JSON=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/APP_SECRETS_JSON")

if [ -n "$RAW_SECRETS_JSON" ] && [ "$RAW_SECRETS_JSON" != "Not Found" ]; then
  echo "Parsing secrets JSON into environment variables..."
  
  # Loop over JSON key-value pairs and add to /etc/environment and current context
  while IFS="=" read -r key value; do
    if [ -n "$key" ]; then
      echo "${key}=${value}" >> /etc/environment
      export "${key}=${value}"
    fi
  done < <(echo "$RAW_SECRETS_JSON" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
fi

# 6. Clone repository using extracted GH_PAT variable
mkdir -p /var/www
cd /var/www
if [ ! -d "school-timetable-management" ]; then
  git clone "https://oauth2:${GH_PAT}@github.com/daniel-modex/school-timetable-management.git"
fi

cd school-timetable-management

# 7. Write application .env file directly from system environment variables
cat <<EOT > .env
DATABASE_URL="${DATABASE_URL:-}"
AUTH_SECRET="${AUTH_SECRET:-}"
EOT

# 8. Build and run app
npm install
npm run build

pm2 start npm --name "timetable-app" -- run start
pm2 save
pm2 startup