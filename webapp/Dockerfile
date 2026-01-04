# --- Stage 1: Build & Dependencies ---
FROM node:20-alpine AS builder

WORKDIR /usr/src/app

# Copy dependency files first to leverage Docker layer caching
COPY package*.json ./

# Install all dependencies (including devDependencies for potential build steps)
RUN npm install

# Copy the rest of the source code
COPY . .

# Optional: Run build scripts (e.g., if using TypeScript or bundling)
# RUN npm run build

# --- Stage 2: Production Runtime ---
FROM node:20-alpine AS runner

# Set environment to production
ENV NODE_ENV=production

WORKDIR /usr/src/app

# Copy only the necessary files from the builder stage
COPY --from=builder /usr/src/app/package*.json ./
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/server.js ./

# Security Best Practice: Don't run as root
USER node

EXPOSE 3000

# Use tini or a similar init process if needed, 
# otherwise direct node execution is fine for simple apps
CMD [ "node", "server.js" ]