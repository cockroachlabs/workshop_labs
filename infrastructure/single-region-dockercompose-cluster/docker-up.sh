#?/bin/bash

export CRDB_VERSION="cockroachdb/cockroach:v21.2.4"
export COMPANY=""
export ENTKEY=""

docker compose up --detach

sleep 120