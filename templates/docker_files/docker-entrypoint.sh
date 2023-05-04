#!/bin/sh

# exit script if there is an error
set -e

echo "ENVIRONMENT: $RAILS_ENV"

# If running the rails server then create or migrate existing database
if [ "${*}" = "./bin/rails server" ]; then
  bin/rails db:prepare
fi

# remove pid file from previous session
rm -f "$APP_PATH"/tmp/pids/server.pid

exec "${@}"
