FROM amazon/aws-cli:2.31.19

COPY cdn/scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/bin/bash"]
