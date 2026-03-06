FROM registry.fedoraproject.org/fedora:latest

# Variables for URLs and versions
ARG CENTOS_VERSION=10
ARG EPEL_VERSION=10
ARG RSYNC_MIRROR=rsync://mirror.in2p3.fr
ARG CENTOS_PATH=/pub/linux/centos-stream/${CENTOS_VERSION}-stream/
ARG EPEL_PATH=/pub/epel/${EPEL_VERSION}/

# Install required tools
RUN dnf install -y rsync nginx && \
    dnf clean all

# Copy exclusions file
COPY rsync-excludes.txt /etc/rsync-excludes.txt

# Build rsync options and sync repositories
RUN <<EOR
set -Eeuo pipefail
mkdir -p /var/www/centos/${CENTOS_VERSION}-stream
mkdir -p /var/www/epel/${EPEL_VERSION}
RSYNC_OPTS="-azH --progress --delete --exclude-from=/etc/rsync-excludes.txt"
rsync ${RSYNC_OPTS} ${RSYNC_MIRROR}${CENTOS_PATH} /var/www/centos/${CENTOS_VERSION}-stream/
rsync ${RSYNC_OPTS} ${RSYNC_MIRROR}${EPEL_PATH} /var/www/epel/${EPEL_VERSION}/
EOR

# Configure nginx
COPY nginx.conf /etc/nginx/nginx.conf

# Expose port 8080
EXPOSE 8080

# Start nginx in foreground mode
CMD ["nginx", "-g", "daemon off;"]
