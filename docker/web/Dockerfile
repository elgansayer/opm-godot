# Stage 1: install relay Node.js dependencies
FROM node:20-alpine AS relay-build
WORKDIR /relay
COPY relay/package*.json ./
RUN npm ci --production

# Stage 2: final image — nginx + embedded relay
FROM nginx:alpine

# Node.js runtime for the WebSocket relay (no npm needed)
RUN apk add --no-cache nodejs

# Relay application
COPY --from=relay-build /relay/node_modules /srv/relay/node_modules
COPY relay/mohaa_relay.js /srv/relay/

# Use repository nginx config for web export + /assets proxying + /relay WS proxy.
COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf

# Custom entrypoint: starts relay, generates CDN config JS, then launches nginx.
COPY docker/web/docker-entrypoint.sh /mohaa-entrypoint.sh
RUN chmod +x /mohaa-entrypoint.sh

# CI exports and patches web build output into /web before publish.
COPY web/ /srv/web/

# Empty assets dir — nginx /assets/ needs this even when using remote CDN.
RUN mkdir -p /srv/assets

# Default CDN proxy config (overwritten by docker-entrypoint.sh at startup).
# Needed so nginx doesn't fail on the `include` directive during config test.
RUN printf 'set $cdn_host "localhost";\nset $cdn_backend "http://127.0.0.1:9999/";\n' \
    > /etc/nginx/conf.d/cdn-proxy-upstream.conf

# Health check: relay responds on /health via nginx proxy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1:12300/health || exit 1

EXPOSE 80
ENTRYPOINT ["/mohaa-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
