#!/bin/sh
set -eu

for database in \
  fcg_identity \
  fcg_payments \
  fcg_library \
  fcg_catalog \
  fcg_promotions \
  fcg_orders \
  fcg_notifications
do
  exists="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT 1 FROM pg_database WHERE datname = '$database'")"

  if [ "$exists" != "1" ]; then
    echo "Creating database $database"
    createdb --owner="$PGUSER" "$database"
  else
    echo "Database $database already exists"
  fi
done
