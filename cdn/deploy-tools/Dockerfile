FROM node:24-alpine

RUN apk add --no-cache bash curl

COPY cdn/scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/bin/bash"]
