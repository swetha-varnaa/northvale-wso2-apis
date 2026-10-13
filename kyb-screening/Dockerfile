FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=8080
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY src ./src
COPY openapi.yaml ./
# Choreo requires a numeric non-root user id between 10000 and 20000
RUN addgroup -g 10014 choreo && adduser -D -u 10014 -G choreo choreouser
USER 10014
EXPOSE 8080
CMD ["node", "src/server.js"]
