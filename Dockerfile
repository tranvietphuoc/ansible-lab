FROM public.ecr.aws/gravitational/teleport-distroless:18.7.6 AS teleport-src

FROM debian:bookworm-slim

COPY --from=teleport-src /usr/local/bin/teleport /usr/local/bin/teleport
COPY --from=teleport-src /usr/local/bin/tctl /usr/local/bin/tctl
COPY --from=teleport-src /usr/local/bin/tsh /usr/local/bin/tsh
COPY --from=teleport-src /etc/teleport /etc/teleport

RUN apt-get update && \
    apt-get install -y --no-install-recommends ansible python3-pip curl openssh-client locales && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Install docker-systemctl-replacement to mock systemd for Ansible
RUN curl -kL https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py -o /usr/bin/systemctl && \
    chmod +x /usr/bin/systemctl
