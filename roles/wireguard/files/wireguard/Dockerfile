FROM linuxserver/wireguard:latest
USER root

RUN apk add --no-cache jq nftables

COPY health_check.sh /usr/local/bin/health_check.sh
RUN chmod +x /usr/local/bin/health_check.sh

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY postup.sh /usr/local/bin/postup.sh
RUN chmod +x /usr/local/bin/postup.sh

COPY predown.sh /usr/local/bin/predown.sh
RUN chmod +x /usr/local/bin/predown.sh

ENTRYPOINT ["/entrypoint.sh"]
