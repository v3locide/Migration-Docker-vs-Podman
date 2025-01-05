# Builder stage
FROM node:22 AS builder

WORKDIR /app

COPY package*.json ./

RUN npm install

COPY . .

RUN npm run build

# Production stage
FROM nginx:stable-alpine AS production

# Remove the default NGINX configuration
RUN rm -rf /etc/nginx/conf.d/default.conf
RUN rm -rf /usr/share/nginx/html/

# Copy your custom NGINX configuration
COPY --from=builder /app/nginx.conf /etc/nginx/conf.d/default.conf

# Copy the build output from the dist folder into the Nginx html directory
COPY --from=builder /app/dist /usr/share/nginx/html

# Add a script to run CPU-intensive tasks
COPY cpu_task.sh /usr/local/bin/cpu_task.sh
RUN chmod +x /usr/local/bin/cpu_task.sh

# Expose port 80
EXPOSE 80

# Start NGINX and the CPU task
CMD ["/bin/sh", "-c", "/usr/local/bin/cpu_task.sh"]
