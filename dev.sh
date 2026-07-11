#!/bin/bash

# Function to detect available container runtime
detect_container_runtime() {
    if command -v podman &> /dev/null; then
        echo "podman"
    elif command -v docker &> /dev/null; then
        echo "docker"
    else
        echo "error" >&2
        echo "Neither podman nor docker found. Please install one of them." >&2
        exit 1
    fi
}

# Detect which container runtime to use
CONTAINER_RUNTIME=$(detect_container_runtime)

# Set compose command based on detected runtime
if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
    COMPOSE_CMD="$CONTAINER_RUNTIME compose -f docker-compose.yml"
    COMPOSE_DEV_CMD="$CONTAINER_RUNTIME compose -f docker-compose-dev.yml"
else
    COMPOSE_CMD="$CONTAINER_RUNTIME compose -f docker-compose.yml"
    COMPOSE_DEV_CMD="$CONTAINER_RUNTIME compose -f docker-compose-dev.yml"
fi

# Set the container runtime for use in commands below
export CONTAINER_RUNTIME

if [[ $CI != "true" ]]; then

echo "=> Kill the local version of Clean Slate..."
bash kill.sh

export NEXT_PUBLIC_VERSION="XXX"
export DOMAIN="localhost"
export NODE_TLS_REJECT_UNAUTHORIZED=0

if [ "$FIREBASE" != "true" ]; then
  export NEXT_PUBLIC_FIREBASE_CONFIG='{}'
  export NEXT_PUBLIC_LOGIN_WITH_APPLE='no'
  export NEXT_PUBLIC_LOGIN_WITH_FACEBOOK='no'
  export NEXT_PUBLIC_LOGIN_WITH_GITHUB='no'
  export NEXT_PUBLIC_LOGIN_WITH_GOOGLE='no'
  export NEXT_PUBLIC_REACT_SENTRY_DSN=''
  export NEXT_PUBLIC_USE_FIREBASE='false'
  export HASURA_GRAPHQL_JWT_SECRET='{ "type": "HS256", "key": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" }'
  export JWT_SIGNING_SECRET="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
fi

$COMPOSE_CMD down -t 0 --remove-orphans

fi

echo "=> Configure the local machine"

if [[ $CI != "true" ]]; then

  export DB_HOST="127.0.0.1"
  export DB_NAME="postgres"
  export DB_PASSWORD="password"
  export DB_PORT="1270"
  export DB_USER="postgres"
  export HASURA_CONSOLE_PORT='9695'
  export HASURA_GRAPHQL_ADMIN_SECRET='secret'
  export HASURA_GRAPHQL_DATABASE_URL="postgres://postgres:password@database:5432/postgres"
  export HASURA_PORT='8080'
  export NEXT_PUBLIC_LEGAL_LINK="XXX"
  export NEXT_PUBLIC_LOGIN_WITH_APPLE="true"
  export NEXT_PUBLIC_LOGIN_WITH_FACEBOOK="true"
  export NEXT_PUBLIC_LOGIN_WITH_GITHUB="true"
  export NEXT_PUBLIC_LOGIN_WITH_GOOGLE="true"
  export NODE_ENV="development"


  if [[ $FIREBASE == "true" ]]; then

    abspath() {
      cd "$(dirname "$1")"
      printf "%s/%s\n" "$(pwd)" "$(basename "$1")"
      cd "$OLDPWD"
    }

    export NEXT_PUBLIC_USE_FIREBASE="true"
    export FIREBASE_PROJECT_ID=$(jq -r .projectId firebase-config.json)
    export NEXT_PUBLIC_FIREBASE_CONFIG=$(jq . firebase-config.json)
    HASURA_GRAPHQL_JWT_SECRET='{ "type": "RS256", "audience": "%s", "issuer": "%s", "jwk_url": "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com" }'
    export HASURA_GRAPHQL_JWT_SECRET=$(printf "$HASURA_GRAPHQL_JWT_SECRET" $FIREBASE_PROJECT_ID https://securetoken.google.com/$FIREBASE_PROJECT_ID)

  fi


  echo "=> Spin up PostgreSQL and Hasura..."
  $COMPOSE_DEV_CMD down -v --remove-orphans -t 0
  $COMPOSE_DEV_CMD pull && $COMPOSE_DEV_CMD up -d

  echo "=> Wait for five seconds for Hasura to get ready..."
  sleep 5;

  echo "=> Run migrations with Hasura..."
  node migrate.js

  hasura console --no-browser --admin-secret 'secret' &
  (cd src && ((npx tsc --watch --preserveWatchOutput) & (npx tsc -p tsconfig-server.json --watch --preserveWatchOutput))) &

fi

# Start the server!

(cd src && ((npx next dev --webpack) & (npx nodemon server.js))) & sleep 5
sudo caddy start -c Caddyfile.dev --adapter caddyfile
