#!/bin/sh
# Generate runtime JS config from container env vars.
# Served by nginx at /mohaa-cdn-config.js (from /tmp/).
# Injected into HTML via sub_filter before </head>.
cat > /tmp/mohaa-cdn-config.js <<EOF
window.MOHAA_CDN_URL='${CDN_URL:-/assets}';
EOF
echo "MOHAAjs: CDN_URL=${CDN_URL:-/assets} written to /tmp/mohaa-cdn-config.js"

# Start the WebSocket-to-UDP relay in the background.
# It listens on port 12300; nginx proxies /relay → 127.0.0.1:12300.
if [ -f /srv/relay/mohaa_relay.js ]; then
    echo "MOHAAjs: Starting WebSocket relay on port 12300"
    node /srv/relay/mohaa_relay.js 12300 &
fi

# Delegate to the official nginx entrypoint.
exec /docker-entrypoint.sh "$@"
