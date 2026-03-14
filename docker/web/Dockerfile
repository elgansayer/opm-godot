FROM nginx:alpine

# Use repository nginx config for web export + /assets proxying.
COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf

# CI exports and patches web build output into /web before publish.
COPY web/ /srv/web/

EXPOSE 80
