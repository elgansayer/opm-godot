FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY mohaa_relay.js ./
EXPOSE 12300
CMD ["node", "mohaa_relay.js"]
