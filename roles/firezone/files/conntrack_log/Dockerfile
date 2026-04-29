FROM alpine:latest

# Configure mirrors with multiple fallbacks (using HTTP due to network policy)
RUN echo "http://dl-cdn.alpinelinux.org/alpine/v3.19/main" > /etc/apk/repositories && \
    echo "http://dl-cdn.alpinelinux.org/alpine/v3.19/community" >> /etc/apk/repositories && \
    echo "http://mirror.yandex.ru/mirrors/alpine/v3.19/main" >> /etc/apk/repositories && \
    echo "http://mirror.yandex.ru/mirrors/alpine/v3.19/community" >> /etc/apk/repositories && \
    echo "http://mirror.hyperdedic.ru/alpinelinux/v3.19/main" >> /etc/apk/repositories && \
    echo "http://mirror.hyperdedic.ru/alpinelinux/v3.19/community" >> /etc/apk/repositories

# Install conntrack-tools and libcap for setcap
RUN apk add --no-cache conntrack-tools libcap

# Grant necessary capabilities to the conntrack binary
RUN setcap cap_net_admin,cap_net_raw+ep $(which conntrack)

# Create a non-root user for better security
RUN addgroup -S conntrack && adduser -S conntrack -G conntrack

# Switch to non-root user
USER conntrack

# Set the entrypoint directly
ENTRYPOINT ["conntrack", "-E", "-e", "NEW"]

# Add labels for better container management
LABEL description="Container for monitoring new connections with conntrack"