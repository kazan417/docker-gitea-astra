# Build stage
FROM golang123 AS build-env
ARG GOPROXY
ARG GOPATH="/go"
ENV GOPROXY=${GOPROXY:-direct}
ARG GITEA_VERSION
ARG TAGS="sqlite sqlite_unlock_notify"
ENV TAGS="bindata timetzdata $TAGS"
ARG CGO_EXTRA_CFLAGS
# Build deps

RUN export PATH=$PATH:/usr/local/go/bin
RUN DEBIAN_FRONTEND='noninteractive' \
    apt update && apt install -y\
    build-essential \
    git \
    nodejs \
    npm \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
 
#ADD https://go.dev/dl/go1.23.2.linux-amd64.tar.gz /usr/ 
#RUN  tar -C /usr/ -xzf /usr/go1.23.2.linux-amd64.tar.gz

# Setup repo
COPY . ${GOPATH}/src/code.gitea.io/gitea
WORKDIR ${GOPATH}/src/code.gitea.io/gitea
RUN curl -qL https://www.npmjs.com/install.sh | sh

# Checkout version if set
#RUN if [ -n "${GITEA_VERSION}" ]; then git checkout "${GITEA_VERSION}"; fi \
RUN  make clean-all build

# Begin env-to-ini build
RUN go build contrib/environment-to-ini/environment-to-ini.go

# Copy local files
COPY docker/root /tmp/local

# Set permissions
RUN chmod 755 /tmp/local/usr/bin/entrypoint \
              /tmp/local/usr/local/bin/gitea \
              /tmp/local/etc/s6/gitea/* \
              /tmp/local/etc/s6/openssh/* \
              /tmp/local/etc/s6/.s6-svscan/* \
              /go/src/code.gitea.io/gitea/gitea \
              /go/src/code.gitea.io/gitea/environment-to-ini
RUN chmod 644 /go/src/code.gitea.io/gitea/contrib/autocompletion/bash_autocomplete

FROM s6-overlay:latest
ARG UID=1380800045
ARG GID=1380800044
LABEL maintainer="maintainers@gitea.io"
ENV S6_OVERLAY_VERSION=3.2.0.2
EXPOSE 22 3000
ENTRYPOINT ["/init"]
RUN DEBIAN_FRONTEND='noninteractive' \
    apt update && apt install -y\
    bash \
    ca-certificates \
    curl \
    gettext \
    git \
    libpam0g \
    ssh \
    sqlite \
    gnupg \
    xz-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
#ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
#RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz
#RUN  rm -f /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz 
RUN  rm -f /tmp/s6-overlay-x86_64.tar.xz
RUN mkdir /var/run/sshd
RUN chmod 0755 /var/run/sshd
COPY su-exec /bin/
RUN addgroup --system --gid ${GID} git
RUN  adduser  --home /data/git --shell /bin/bash --ingroup git --uid ${UID} git 
RUN chown git:git /data
RUN chmod -R a+r /package /command
ENV USER=git
ENV GITEA_CUSTOM=/data/gitea
VOLUME ["/data"]
ENTRYPOINT ["/usr/bin/entrypoint"]
#RUN  echo "git:${PASS}" | chpasswd -e
#USER git
CMD ["/command/s6-svscan", "/etc/s6"]

COPY --chown=git --from=build-env /tmp/local /
COPY --chown=git --from=build-env /go/src/code.gitea.io/gitea/gitea /app/gitea/gitea
COPY --chown=git --from=build-env /go/src/code.gitea.io/gitea/environment-to-ini /usr/local/bin/environment-to-ini
COPY --chown=git --from=build-env /go/src/code.gitea.io/gitea/contrib/autocompletion/bash_autocomplete /etc/profile.d/gitea_bash_autocomplete.sh
