FROM debian:bullseye-20220125-slim

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    BEASTPORT=30005 \
    BRANCH_READSB=dev \
    READSB_GIT_URL="https://github.com/wiedehopf/readsb.git" \
    GITPATH_TAR1090=/opt/tar1090 \
    GITPATH_TAR1090_DB=/opt/tar1090-db \
    GITPATH_TAR1090_AC_DB=/opt/tar1090-ac-db \
    HTTP_ACCESS_LOG="false" \
    HTTP_ERROR_LOG="true" \
    TAR1090_INSTALL_DIR=/usr/local/share/tar1090 \
    MLATPORT=30105 \
    INTERVAL=8 \
    HISTORY_SIZE=450 \
    ENABLE_978=no \
    URL_978="http://127.0.0.1/skyaware978" \
    GZIP_LVL=3 \
    CHUNK_SIZE=60 \
    INT_978=1 \
    PF_URL="http://127.0.0.1:30053/ajax/aircraft" \
    COMPRESS_978="" \
    TAR1090_GIT_URL="https://github.com/wiedehopf/tar1090.git" \
    TAR1090_GIT_BRANCH="master" \
    TIMELAPSE1090_GIT_URL="https://github.com/wiedehopf/timelapse1090.git" \
    TIMELAPSE1090_GIT_BRANCH="master" \
    GITPATH_TIMELAPSE1090=/opt/timelapse1090 \
    READSB_MAX_RANGE=300 \
    TIMELAPSE1090_SOURCE=/run/readsb \
    TIMELAPSE1090_INTERVAL=10 \
    TIMELAPSE1090_HISTORY=24 \
    TIMELAPSE1090_CHUNK_SIZE=240 \
    UPDATE_TAR1090="true" \
    PTRACKS=8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY rootfs/ /

RUN set -x && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
      bc \
      ca-certificates \
      curl \
      file \
      gcc \
      git \
      gnupg \
      jq \
      make \
      ncurses-dev \
      nginx-light \
      p7zip-full \
      procps \
      wget \
      zlib1g \
      zlib1g-dev \
      && \
    rm /etc/nginx/sites-enabled/default && \
    echo "========== Install tar1090-db ==========" && \
    git clone --depth 1 https://github.com/wiedehopf/tar1090-db "${GITPATH_TAR1090_DB}" && \
    pushd "${GITPATH_TAR1090_DB}" || exit 1 && \
    VERSION_TAR1090_DB=$(git log | head -1 | tr -s " " "_") && \
    echo "tar1090-db ${VERSION_TAR1090_DB}" >> /VERSIONS && \
    popd && \
    echo "========== Install tar1090 ==========" && \
    git clone --single-branch -b "${TAR1090_GIT_BRANCH}" --depth 1 "${TAR1090_GIT_URL}" "${GITPATH_TAR1090}" && \
    pushd "${GITPATH_TAR1090}" && \
    VERSION_TAR1090=$(git log | head -1 | tr -s " " "_") && \
    echo "tar1090 ${VERSION_TAR1090}" >> /VERSIONS && \
    popd && \
    cp -Rv /etc/nginx.tar1090/* /etc/nginx/ && \
    rm -rvf /etc/nginx.tar1090 && \
    echo "========== Install timelapse1090 ==========" && \
    git clone -b "${TIMELAPSE1090_GIT_BRANCH}" "${TIMELAPSE1090_GIT_URL}" "${GITPATH_TIMELAPSE1090}" && \
    pushd "${GITPATH_TIMELAPSE1090}" && \
    VERSION_TIMELAPSE1090=$(git log | head -1 | tr -s " " "_") || true && \
    echo "" && \
    echo "timelapse1090 ${VERSION_TIMELAPSE1090}" >> /VERSIONS && \
    popd && \
    mkdir -p /var/timelapse1090 && \
    echo "========== Building readsb ==========" && \
    git clone --branch="${BRANCH_READSB}" --single-branch --depth=1 "${READSB_GIT_URL}" /src/readsb && \
    pushd /src/readsb && \
    #export BRANCH_READSB=$(git tag --sort="-creatordate" | head -1) && \
    make RTLSDR=no BLADERF=no PLUTOSDR=no HAVE_BIASTEE=no OPTIMIZE="-O3" && \
    cp -v /src/readsb/readsb /usr/local/bin/readsb && \
    cp -v /src/readsb/viewadsb /usr/local/bin/viewadsb && \
    mkdir -p /var/globe_history && \
    echo "readsb $(/usr/local/bin/readsb --version)" >> /VERSIONS && \
    popd && \
    echo "========== Install AircraftDB ==========" && \
    mkdir -p $GITPATH_TAR1090_AC_DB && \
    curl https://raw.githubusercontent.com/wiedehopf/tar1090-db/csv/aircraft.csv.gz > $GITPATH_TAR1090_AC_DB/aircraft.csv.gz && \
    echo "========== Install s6-overlay ==========" && \
    curl -s https://raw.githubusercontent.com/mikenye/deploy-s6-overlay/master/deploy-s6-overlay.sh | sh && \
    # Versions
    grep -v tar1090-db /VERSIONS | grep tar1090 | cut -d " " -f 2 > /CONTAINER_VERSION && \
    echo "========== Clean-up ==========" && \
    apt-get remove -y \
      file \
      gcc \
      gnupg \
      make \
      ncurses-dev \
      zlib1g-dev \
      && \
    apt-get autoremove -y && \
    rm -rf /tmp/* /src /var/lib/apt/lists/* && \
    cat /VERSIONS

ENTRYPOINT [ "/init" ]

EXPOSE 80/tcp

# Add healthcheck
HEALTHCHECK --start-period=3600s --interval=600s CMD /healthcheck.sh
