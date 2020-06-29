FROM debian:stable-slim

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    BEASTPORT=30005 \
    BRANCH_READSB=dev \
    READSB_GIT_URL="https://github.com/wiedehopf/readsb.git" \
    GITPATH_TAR1090=/opt/tar1090 \
    GITPATH_TAR1090_DB=/opt/tar1090-db \
    HTTP_ACCESS_LOG="false" \
    HTTP_ERROR_LOG="true" \
    TAR1090_INSTALL_DIR=/usr/local/share/tar1090 \
    MLATPORT=30105

RUN set -x && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
      ca-certificates \
      curl \
      file \
      gcc \
      git \
      gnupg \
      jq \
      libc-dev \
      make \
      ncurses-dev \
      nginx-light \
      p7zip-full \
      zlib1g \
      zlib1g-dev \
      && \
    rm /etc/nginx/sites-enabled/default && \
    echo "========== Install tar1090-db ==========" && \
    git clone --depth 1 https://github.com/wiedehopf/tar1090-db "${GITPATH_TAR1090_DB}" && \
    cd "${GITPATH_TAR1090_DB}" || exit 1 && \
    VERSION_TAR1090_DB=$(git log | head -1 | tr -s " " "_") && \
    echo "tar1090-db ${VERSION_TAR1090_DB}" >> /VERSIONS && \
    echo "========== Install tar1090 ==========" && \
    git clone --single-branch -b master --depth 1 https://github.com/wiedehopf/tar1090 "${GITPATH_TAR1090}" && \
    cd "${GITPATH_TAR1090}" && \
    VERSION_TAR1090=$(git log | head -1 | tr -s " " "_") && \
    echo "tar1090 ${VERSION_TAR1090}" >> /VERSIONS && \
    echo "========== Building readsb ==========" && \
    git clone --branch="${BRANCH_READSB}" --single-branch --depth=1 "${READSB_GIT_URL}" /src/readsb && \
    cd /src/readsb && \
    #export BRANCH_READSB=$(git tag --sort="-creatordate" | head -1) && \
    make RTLSDR=no BLADERF=no PLUTOSDR=no HAVE_BIASTEE=no && \
    cp -v /src/readsb/readsb /usr/local/bin/readsb && \
    cp -v /src/readsb/viewadsb /usr/local/bin/viewadsb && \
    mkdir -p /run/readsb && \
    mkdir -p /var/globe_history && \
    echo "readsb $(/usr/local/bin/readsb --version)" >> /VERSIONS && \
    echo "========== Install s6-overlay ==========" && \
    curl -s https://raw.githubusercontent.com/mikenye/deploy-s6-overlay/master/deploy-s6-overlay.sh | sh && \
    echo "========== Clean-up ==========" && \
    apt-get remove -y \
      file \
      gcc \
      gnupg \
      libc-dev \
      make \
      ncurses-dev \
      zlib1g-dev \
      && \
    apt-get autoremove -y && \
    rm -rf /tmp/* /src /var/lib/apt/lists/* && \
    cat /VERSIONS

COPY rootfs/ /

ENTRYPOINT [ "/init" ]

EXPOSE 80/tcp
