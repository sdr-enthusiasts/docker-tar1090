FROM ghcr.io/sdr-enthusiasts/docker-baseimage:wreadsb

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    BEASTPORT=30005 \
    GITPATH_TAR1090=/opt/tar1090 \
    GITPATH_TAR1090_DB=/opt/tar1090-db \
    GITPATH_TAR1090_AC_DB=/opt/tar1090-ac-db \
    GITPATH_TIMELAPSE1090=/opt/timelapse1090 \
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
    TEMP_PACKAGES=() && \
    KEPT_PACKAGES=() && \
    # Essentials (git is kept for aircraft db updates)
    KEPT_PACKAGES+=(git) && \
    TEMP_PACKAGES+=(build-essential) && \
    # tar1090
    KEPT_PACKAGES+=(nginx-light) && \
    # healthchecks
    KEPT_PACKAGES+=(jq) && \
    # install packages
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ${KEPT_PACKAGES[@]} \
        ${TEMP_PACKAGES[@]} \
        && \
    # nginx: remove default config
    rm /etc/nginx/sites-enabled/default && \
    # tar1090-db: clone
    git clone --depth 1 https://github.com/wiedehopf/tar1090-db "${GITPATH_TAR1090_DB}" && \
    # tar1090-db: document version
    pushd "${GITPATH_TAR1090_DB}" || exit 1 && \
    VERSION_TAR1090_DB=$(git log | head -1 | tr -s " " "_") && \
    echo "tar1090-db ${VERSION_TAR1090_DB}" >> /VERSIONS && \
    popd && \
    # tar1090: clone
    git clone --single-branch --depth 1 "https://github.com/wiedehopf/tar1090.git" "${GITPATH_TAR1090}" && \
    pushd "${GITPATH_TAR1090}" && \
    VERSION_TAR1090=$(git log | head -1 | tr -s " " "_") && \
    echo "tar1090 ${VERSION_TAR1090}" >> /VERSIONS && \
    popd && \
    # tar1090: add nginx config
    cp -Rv /etc/nginx.tar1090/* /etc/nginx/ && \
    rm -rvf /etc/nginx.tar1090 && \
    # timelapse1090
    git clone --single-branch --depth 1 "https://github.com/wiedehopf/timelapse1090.git" "${GITPATH_TIMELAPSE1090}" && \
    pushd "${GITPATH_TIMELAPSE1090}" && \
    VERSION_TIMELAPSE1090=$(git log | head -1 | tr -s " " "_") || true && \
    echo "timelapse1090 ${VERSION_TIMELAPSE1090}" >> /VERSIONS && \
    popd && \
    mkdir -p /var/timelapse1090 && \
    # aircraft-db
    mkdir -p "$GITPATH_TAR1090_AC_DB" && \
    curl "https://raw.githubusercontent.com/wiedehopf/tar1090-db/csv/aircraft.csv.gz" > "$GITPATH_TAR1090_AC_DB/aircraft.csv.gz" && \
    # Clean-up.
    apt-get remove -y ${TEMP_PACKAGES[@]} && \
    apt-get autoremove -y && \
    rm -rf /src/* /tmp/* /var/lib/apt/lists/* && \
    # document versions
    grep -v tar1090-db /VERSIONS | grep tar1090 | cut -d " " -f 2 > /CONTAINER_VERSION && \
    cat /VERSIONS

EXPOSE 80/tcp

# Add healthcheck
HEALTHCHECK --start-period=300s --interval=300s CMD /healthcheck.sh
