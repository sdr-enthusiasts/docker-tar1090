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
    PF_URL="http://127.0.0.1:30053/ajax/aircraft" \
    COMPRESS_978="" \
    TIMELAPSE1090_SOURCE=/run/readsb \
    TIMELAPSE1090_INTERVAL=10 \
    TIMELAPSE1090_HISTORY=24 \
    TIMELAPSE1090_CHUNK_SIZE=240 \
    GRAPHS1090_REDUCE_IO="false" \
    UPDATE_TAR1090="true" \
    PTRACKS=8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# only copy files necessary for the build, copy whole rootfs later
# this improves build caching when changing service and startup scripting
COPY rootfs/tar1090-install.sh /
COPY rootfs/etc/nginx.tar1090 /etc/nginx.tar1090

# add telegraf binary
##telegraf##COPY --from=telegraf /usr/bin/telegraf /usr/bin/telegraf

RUN set -x && \
    TEMP_PACKAGES=() && \
    KEPT_PACKAGES=() && \
    # Essentials (git is kept for aircraft db updates)
    KEPT_PACKAGES+=(git) && \
    # tar1090
    KEPT_PACKAGES+=(nginx-light) && \
    # graphs1090
    KEPT_PACKAGES+=(collectd-core) && \
    KEPT_PACKAGES+=(rrdtool) && \
    KEPT_PACKAGES+=(unzip) && \
    KEPT_PACKAGES+=(bash-builtins) && \
    KEPT_PACKAGES+=(libpython3.11) && \
    KEPT_PACKAGES+=(libncurses6) && \
    # healthchecks
    KEPT_PACKAGES+=(jq) && \
    # install packages
    apt-get update && \
    apt-get install -y --no-install-recommends \
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
    bash /tar1090-install.sh /run/readsb webroot "${TAR1090_INSTALL_DIR}" && \
    # change some /run/tar1090-webroot to /run/readsb to make work with existing docker scripting
    sed -i -e 's#/run/tar1090-webroot/#/run/readsb/#' /usr/local/share/tar1090/nginx-tar1090-webroot.conf && \
    # tar1090-db: document version
    pushd "${TAR1090_UPDATE_DIR}/git-db" || exit 1 && \
    bash -ec 'echo "tar1090-db $(git log | head -1 | tr -s " " "_")" >> /VERSIONS' && \
    popd && \
    # tar1090: document version
    pushd "${TAR1090_UPDATE_DIR}/git" || exit 1 && \
    bash -ec 'echo "tar1090 $(git log | head -1 | tr -s " " "_")" >> /VERSIONS' && \
    popd && \
    # tar1090: remove tar1090-update files as they're not needed unless tar1090-update is active
    rm -rf "${TAR1090_UPDATE_DIR}" && \
    # tar1090: add nginx config
    cp -Rv /etc/nginx.tar1090/* /etc/nginx/ && \
    # timelapse1090
    git clone --single-branch --depth 1 "https://github.com/wiedehopf/timelapse1090.git" "${GITPATH_TIMELAPSE1090}" && \
    pushd "${GITPATH_TIMELAPSE1090}" && \
    bash -ec 'echo "timelapse1090 $(git log | head -1 | tr -s " " "_")" >> /VERSIONS' && \
    # remove unused .git dir to slightly reduce image size
    rm -rf "${GITPATH_TIMELAPSE1090}/.git" && \
    popd && \
    mkdir -p /var/timelapse1090 && \
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
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L147
    cp -v \
    /usr/share/graphs1090/git/malarky.conf \
    /usr/share/graphs1090/ \
    && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L148
    chmod -v a+x /usr/share/graphs1090/*.sh && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L151
    cp -v \
    /usr/share/graphs1090/git/collectd.conf \
    /etc/collectd/collectd.conf \
    && \
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L171
    sed -i '/<Plugin "interface">/a\ \ \ \ Interface "eth0"' /etc/collectd/collectd.conf && \
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
    # ref: https://github.com/wiedehopf/graphs1090/blob/151e63a810d6b087518992d4f366d9776c5c826b/install.sh#L218
    sed -i -e 's?URL .*?URL "file:///usr/share/graphs1090/data-symlink"?' /etc/collectd/collectd.conf && \
    ## Lines below merge the tar1090 collectd config with the graphs1090 collectd config
    # remove the default syslog config in collectd.conf
    sed -i '/<Plugin\ syslog>/,/<\/Plugin>/d' /etc/collectd/collectd.conf && \
    # replace syslog plugin with logfile plugin in collectd.conf
    sed -i 's/LoadPlugin\ syslog/LoadPlugin logfile/' /etc/collectd/collectd.conf && \
    # add configuration to log to STDOUT in collectd.conf ("/a" == append lines after match)
    sed -i '/LoadPlugin\ logfile/a\\n<Plugin\ logfile>\n<\/Plugin>' /etc/collectd/collectd.conf && \
    sed -i '/<Plugin\ logfile>/a\ \ \ \ PrintSeverity\ true' /etc/collectd/collectd.conf && \
    sed -i '/<Plugin\ logfile>/a\ \ \ \ Timestamp\ false' /etc/collectd/collectd.conf && \
    sed -i '/<Plugin\ logfile>/a\ \ \ \ File\ STDOUT' /etc/collectd/collectd.conf && \
    sed -i '/<Plugin\ logfile>/a\ \ \ \ LogLevel\ "notice"' /etc/collectd/collectd.conf && \
    # add tar1090 specific stuff
    sed -i '$a\\n' /etc/collectd/collectd.conf && \
    sed -i '$aFQDNLookup\ true' /etc/collectd/collectd.conf && \
    # set up base telegraf config directories
    ##telegraf##mkdir -p /etc/telegraf/telegraf.d && \
    # document telegraf version
    ##telegraf##bash -ec "telegraf --version >> /VERSIONS" && \
    # Clean-up.
    apt-get remove -y ${TEMP_PACKAGES[@]} && \
    apt-get autoremove -y && \
    apt-get clean -q -y && \
    rm -rf /src/* /tmp/* /var/lib/apt/lists/* && \
    # document versions
    bash -ec 'grep -v tar1090-db /VERSIONS | grep tar1090 | cut -d " " -f 2 > /CONTAINER_VERSION' && \
    cat /VERSIONS && \
    # Add Container Version
    branch="##BRANCH##" && \
    [[ "${branch:0:1}" == "#" ]] && branch="main" || true && \
    git clone --depth=1 -b $branch https://github.com/sdr-enthusiasts/docker-tar1090.git /tmp/clone && \
    pushd /tmp/clone && \
    bash -ec 'echo "$(TZ=UTC date +%Y%m%d-%H%M%S)_$(git rev-parse --short HEAD)_$(git branch --show-current)" > /.CONTAINER_VERSION' && \
    popd && \
    rm -rf /tmp/*

COPY rootfs/ /

EXPOSE 80/tcp

# Add healthcheck
HEALTHCHECK --start-period=600s --interval=600s CMD /healthcheck.sh
