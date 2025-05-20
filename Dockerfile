# Note - do not remove the ##telegraf## tags from this file - they are used to build a tag that includes the telegraf binary
##telegraf##FROM telegraf:1.26 AS telegraf

##telegraf##RUN touch /tmp/emptyfile

FROM ghcr.io/sdr-enthusiasts/docker-baseimage:wreadsb

ENV BEASTPORT=30005 \
    GITPATH_TIMELAPSE1090=/opt/timelapse1090 \
    HTTP_ACCESS_LOG="false" \
    HTTP_ERROR_LOG="true" \
    TAR1090_INSTALL_DIR=/usr/local/share/tar1090 \
    TAR1090_UPDATE_DIR=/var/globe_history/tar1090-update \
    MLATPORT=30105 \
    INTERVAL=8 \
    HISTORY_SIZE=450 \
    ENABLE_978=no \
    GZIP_LVL=3 \
    CHUNK_SIZE=60 \
    INT_978=1 \
    COMPRESS_978="" \
    TIMELAPSE1090_SOURCE=/run/readsb \
    TIMELAPSE1090_INTERVAL=10 \
    TIMELAPSE1090_HISTORY=24 \
    TIMELAPSE1090_CHUNK_SIZE=240 \
    GRAPHS1090_REDUCE_IO="false" \
    UPDATE_TAR1090="true" \
    PTRACKS=8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# add telegraf binary
##telegraf##COPY --from=telegraf /usr/bin/telegraf /usr/bin/telegraf

RUN \
    --mount=type=bind,source=./,target=/app/ \
    set -x && \
    TEMP_PACKAGES=() && \
    KEPT_PACKAGES=() && \
    TEMP_PACKAGES+=(git) && \
    # tar1090
    KEPT_PACKAGES+=(nginx-light) && \
    # graphs1090
    KEPT_PACKAGES+=(collectd-core) && \
    KEPT_PACKAGES+=(rrdtool) && \
    KEPT_PACKAGES+=(bash-builtins) && \
    KEPT_PACKAGES+=(libpython3.11) && \
    KEPT_PACKAGES+=(libncurses6) && \
    # healthchecks
    KEPT_PACKAGES+=(jq) && \
    # install packages
    apt-get update && \
    apt-get install -y --no-install-suggests --no-install-recommends \
    ${KEPT_PACKAGES[@]} \
    ${TEMP_PACKAGES[@]} \
    && \
    # grab the bias t scripts
    curl -o /etc/s6-overlay/scripts/09-rtlsdr-biastee-init https://raw.githubusercontent.com/sdr-enthusiasts/sdre-bias-t-common/main/09-rtlsdr-biastee-init && \
    curl -o /etc/s6-overlay/scripts/09-rtlsdr-biastee-down  https://raw.githubusercontent.com/sdr-enthusiasts/sdre-bias-t-common/main/09-rtlsdr-biastee-down && \
    chmod +x /etc/s6-overlay/scripts/09-rtlsdr-biastee-init && \
    chmod +x /etc/s6-overlay/scripts/09-rtlsdr-biastee-down && \
    # nginx: remove default config
    rm /etc/nginx/sites-enabled/default && \
    # tar1090: install using project copy of original script
    bash /app/rootfs/tar1090-install.sh /run/readsb webroot "${TAR1090_INSTALL_DIR}" && \
    # tar1090-db: document version
    echo "tar1090-db $(cat ${TAR1090_UPDATE_DIR}/git-db/version)" >> VERSIONS && \
    # tar1090: document version
    echo "tar1090 $(cat ${TAR1090_UPDATE_DIR}/git/version)" >> VERSIONS && \
    # tar1090: remove tar1090-update files as they're not needed unless tar1090-update is active
    rm -rf "${TAR1090_UPDATE_DIR}" && \
    # tar1090: add nginx config
    cp -Rv /app/rootfs/etc/nginx.tar1090/* /etc/nginx/ && \
    # copy nginx config out of tar1090 install directory which might be updated while the container is running
    cp -v "${TAR1090_INSTALL_DIR}/nginx-tar1090-webroot.conf" /etc/nginx/ && \
    # aircraft-db, file in TAR1090_UPDATE_DIR will be preferred when starting readsb if tar1090-update enabled
    curl -o "${TAR1090_INSTALL_DIR}/aircraft.csv.gz" "https://raw.githubusercontent.com/wiedehopf/tar1090-db/csv/aircraft.csv.gz" && \
    # clone graphs1090 repo
    git clone \
    -b master \
    --depth 1 \
    https://github.com/wiedehopf/graphs1090.git \
    /usr/share/graphs1090/git \
    && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L145
    cp -v \
    /usr/share/graphs1090/git/dump1090.db \
    /usr/share/graphs1090/git/dump1090.py \
    /usr/share/graphs1090/git/system_stats.py \
    /usr/share/graphs1090/git/LICENSE \
    /usr/share/graphs1090/ \
    && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L146
    cp -v \
    /usr/share/graphs1090/git/*.sh \
    /usr/share/graphs1090/ \
    && \
    # adjust scripts using systemctl for container (only affects speciality scripts)
    bash /usr/share/graphs1090/git/adjust-scripts-s6-sh && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L147
    cp -v \
    /usr/share/graphs1090/git/malarky.conf \
    /usr/share/graphs1090/ \
    && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L148
    chmod -v a+x /usr/share/graphs1090/*.sh && \
    # collectd.conf customization done in graphs1090-init
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L179
    cp -rv \
    /usr/share/graphs1090/git/html \
    /usr/share/graphs1090/ \
    && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L180
    cp -v \
    /usr/share/graphs1090/git/default \
    /etc/default/graphs1090 \
    && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L302
    cp -v \
    /usr/share/graphs1090/git/nginx-graphs1090.conf \
    /usr/share/graphs1090/ \
    && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L212
    mkdir -p /usr/share/graphs1090/data-symlink && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L217
    ln -vsnf /run/readsb /usr/share/graphs1090/data-symlink/data && \
    # set up base telegraf config directories
    ##telegraf##mkdir -p /etc/telegraf/telegraf.d && \
    # document telegraf version
    ##telegraf##bash -ec "telegraf --version >> /VERSIONS" && \
    # Add Container Version
    branch="##BRANCH##" && \
    { [[ "${branch:0:1}" == "#" ]] && branch="main" || true; } && \
    git clone --depth=1 -b $branch https://github.com/sdr-enthusiasts/docker-tar1090.git /tmp/clone && \
    pushd /tmp/clone && \
    bash -ec 'echo "$(TZ=UTC date +%Y%m%d-%H%M%S)_$(git rev-parse --short HEAD)_$(git branch --show-current)" > /.CONTAINER_VERSION' && \
    popd && \
    # Clean-up.
    apt-get autoremove -q -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 -y ${TEMP_PACKAGES[@]} && \
    apt-get clean -q -y && \
    rm -rf /src/* /tmp/* /var/lib/apt/lists/* /var/cache/* && \
    bash /scripts/clean-build.sh && \
    # document versions
    cat /VERSIONS

COPY rootfs/ /

EXPOSE 80/tcp

# Add healthcheck
HEALTHCHECK --start-period=600s --interval=600s CMD /healthcheck.sh
