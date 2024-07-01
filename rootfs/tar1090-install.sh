#!/bin/bash
# shellcheck shell=bash disable=SC2016


set -e
trap 'echo "[ERROR] Error in line $LINENO when executing: $BASH_COMMAND"' ERR

srcdir=/run/readsb
repo="https://github.com/wiedehopf/tar1090"
db_repo="https://github.com/wiedehopf/tar1090-db"

# optional command line options for this install script
# $1: data source directory
# $2: web path, default is "tar1090", use "webroot" to place the install at /
# $3: specify install path
# $4: specify git path as source instead of pulling from git

ipath=/usr/local/share/tar1090
if [[ -n "$3" ]]; then ipath="$3"; fi

if [[ -n "$4" ]] && grep -qs -e 'tar1090' "$4/install.sh"; then git_source="$4"; fi

lighttpd=no
nginx=no
function useSystemd () { command -v systemd &>/dev/null; }

gpath="$TAR1090_UPDATE_DIR"
if [[ -z "$gpath" ]]; then gpath="$ipath"; fi

mkdir -p "$ipath"
mkdir -p "$gpath"

if [ -d /etc/lighttpd/conf.d/ ] && ! [ -d /etc/lighttpd/conf-enabled/ ] && ! [ -d /etc/lighttpd/conf-available ] && command -v lighttpd &>/dev/null
then
    ln -s /etc/lighttpd/conf.d /etc/lighttpd/conf-enabled
    mkdir -p /etc/lighttpd/conf-available
fi

if [ -d /etc/lighttpd/conf-enabled/ ] && [ -d /etc/lighttpd/conf-available ] && command -v lighttpd &>/dev/null
then
    lighttpd=yes
fi

if command -v nginx &>/dev/null
then
    nginx=yes
fi

dir=$(pwd)

if (( $( { du -s "$gpath/git-db" 2>/dev/null || echo 0; } | cut -f1) > 150000 )); then
    rm -rf "$gpath/git-db"
fi

function copyNoClobber() {
    if ! [[ -f "$2" ]]; then
        cp "$1" "$2"
    fi
}

function getGIT() {
    # getGIT $REPO $BRANCH $TARGET (directory)
    if [[ -z "$1" ]] || [[ -z "$2" ]] || [[ -z "$3" ]]; then echo "getGIT wrong usage, check your script or tell the author!" 1>&2; return 1; fi
    REPO="$1"; BRANCH="$2"; TARGET="$3"; pushd /tmp >/dev/null
    rm -rf "$TARGET"; tmp=$(mktemp)
    if wget --no-verbose -O "$tmp" "$REPO/archive/refs/heads/$BRANCH.tar.gz" && mkdir -p "$tmp.folder" && tar xf "$tmp" -C "$tmp.folder" >/dev/null; then
        if mv -fT "$tmp.folder/$(ls "$tmp.folder")" "$TARGET"; then rm -rf "$tmp" "$tmp.folder"; popd > /dev/null; return 0; fi
    fi
    rm -rf "$tmp" "$tmp.folder"; popd > /dev/null; return 1;
}

DB_VERSION_NEW=$(curl --connect-timeout 2 --silent --show-error "https://raw.githubusercontent.com/wiedehopf/tar1090-db/master/version")
if  [[ "$(cat "$gpath/git-db/version" 2>/dev/null)" != "$DB_VERSION_NEW" ]]; then
    getGIT "$db_repo" "master" "$gpath/git-db" || true
fi

if ! cd "$gpath/git-db"
then
    echo "Unable to download files, exiting! (Maybe try again?)"
    exit 1
fi

DB_VERSION=$(cat "$gpath/git-db/version")

cd "$dir"

if [[ "$1" == "test" ]] || [[ -n "$git_source" ]]; then
    mkdir -p "$gpath/git"
    rm -rf "$gpath/git"/* || true
    if [[ -n "$git_source" ]]; then
        cp -r "$git_source"/* "$gpath/git"
    else
        cp -r ./* "$gpath/git"
    fi
    cd "$gpath/git"
    TAR_VERSION="$(cat version)_dirty"
else
    VERSION_NEW=$(curl --connect-timeout 2 --silent --show-error "https://raw.githubusercontent.com/wiedehopf/tar1090/master/version")
    if  [[ "$(cat "$gpath/git/version" 2>/dev/null)" != "$VERSION_NEW" ]]; then
        if ! getGIT "$repo" "master" "$gpath/git"; then
            echo "Unable to download files, exiting! (Maybe try again?)"
            exit 1
        fi
    fi
    if ! cd "$gpath/git"; then
        echo "Unable to download files, exiting! (Maybe try again?)"
        exit 1
    fi
    TAR_VERSION="$(cat version)"
fi


if [[ -n $1 ]] && [ "$1" != "test" ] ; then
    srcdir=$1
elif [ -f /etc/default/tar1090_instances ]; then
    true
elif [[ -f /run/dump1090-fa/aircraft.json ]] ; then
    srcdir=/run/dump1090-fa
elif [[ -f /run/readsb/aircraft.json ]]; then
    srcdir=/run/readsb
elif [[ -f /run/adsbexchange-feed/aircraft.json ]]; then
    srcdir=/run/adsbexchange-feed
elif [[ -f /run/dump1090/aircraft.json ]]; then
    srcdir=/run/dump1090
elif [[ -f /run/dump1090-mutability/aircraft.json ]]; then
    srcdir=/run/dump1090-mutability
elif [[ -f /run/skyaware978/aircraft.json ]]; then
    srcdir=/run/skyaware978
else
    echo --------------
    echo FATAL: could not find aircraft.json in any of the usual places!
    echo "checked these: /run/readsb /run/dump1090-fa /run/dump1090 /run/dump1090-mutability /run/adsbexchange-feed /run/skyaware978"
    echo --------------
    echo "You need to have a decoder installed first, readsb is recommended:"
    echo "https://github.com/wiedehopf/adsb-scripts/wiki/Automatic-installation-for-readsb"
    echo --------------
    exit 1
fi

if [[ -n $2 ]]; then
    instances="$srcdir $2"
elif [[ -n $1 ]] && [ "$1" != "test" ] ; then
    instances="$1 tar1090"
elif [ -f /etc/default/tar1090_instances ]; then
    instances=$(</etc/default/tar1090_instances)
else
    instances="$srcdir tar1090"
fi

if [[ -d /usr/local/share/adsbexchange-978 ]]; then
    instances+="\n /run/adsbexchange-978 ax978"
fi

instances=$(echo -e "$instances" | grep -v -e '^#')


if ! diff tar1090.sh "$ipath"/tar1090.sh &>/dev/null; then
    changed=yes
    while read -r srcdir instance; do
        if [[ -z "$srcdir" || -z "$instance" ]]; then
            continue
        fi

        if [[ "$instance" != "tar1090" ]]; then
            service="tar1090-$instance"
        else
            service="tar1090"
        fi
        if useSystemd; then
            systemctl stop "$service" 2>/dev/null || true
        fi
    done < <(echo "$instances")
    cp tar1090.sh "$ipath"
fi


# copy over base files
cp install.sh uninstall.sh getupintheair.sh LICENSE README.md "$ipath"
cp default "$ipath/example_config_dont_edit"
cp html/config.js "$ipath/example_config.js"
rm -f "$ipath/default"

# create 95-tar1090-otherport.conf
{
    echo '# serve tar1090 directly on port 8504'
    echo '$SERVER["socket"] == ":8504" {'
    cat 88-tar1090.conf
    echo '}'
} > 95-tar1090-otherport.conf

services=()
names=""
otherport=""

while read -r srcdir instance
do
    if [[ -z "$srcdir" || -z "$instance" ]]; then
        continue
    fi
    TMP="$ipath/.instance_tmp"
    rm -rf "$TMP"
    mkdir -p "$TMP"
    chmod 755 "$TMP"

    if [[ "$instance" != "tar1090" ]]; then
        html_path="$ipath/html-$instance"
        service="tar1090-$instance"
    else
        html_path="$ipath/html"
        service="tar1090"
    fi
    services+=("$service")
    names+="$instance "

    # don't overwrite existing configuration
    useSystemd && copyNoClobber default /etc/default/"$service"

    sed -i.orig -e "s?SOURCE_DIR?$srcdir?g" -e "s?SERVICE?${service}?g" \
        -e "s?/INSTANCE??g" -e "s?HTMLPATH?$html_path?g" 95-tar1090-otherport.conf

    if [[ "$instance" == "webroot" ]]; then
        sed -i.orig -e "s?SOURCE_DIR?$srcdir?g" -e "s?SERVICE?${service}?g" \
            -e "s?/INSTANCE??g" -e "s?HTMLPATH?$html_path?g" 88-tar1090.conf
        sed -i.orig -e "s?SOURCE_DIR?$srcdir?g" -e "s?SERVICE?${service}?g" \
            -e "s?/INSTANCE/?/?g" -e "s?HTMLPATH?$html_path?g" nginx.conf
        sed -i -e "s?/INSTANCE?/?g" nginx.conf
    else
        sed -i.orig -e "s?SOURCE_DIR?$srcdir?g" -e "s?SERVICE?${service}?g" \
            -e "s?INSTANCE?$instance?g" -e "s?HTMLPATH?$html_path?g" 88-tar1090.conf
        sed -i.orig -e "s?SOURCE_DIR?$srcdir?g" -e "s?SERVICE?${service}?g" \
            -e "s?INSTANCE?$instance?g" -e "s?HTMLPATH?$html_path?g" nginx.conf
    fi

    if [[ $lighttpd == yes ]] && lighttpd -v | grep -E 'lighttpd/1.4.(5[6-9]|[6-9])' -qs; then
        sed -i -e 's/compress.filetype/deflate.mimetypes/' 88-tar1090.conf
        sed -i -e 's/compress.filetype/deflate.mimetypes/' 95-tar1090-otherport.conf
        if ! grep -qs -e '^[^#]*"mod_deflate"' /etc/lighttpd/lighttpd.conf /etc/lighttpd/conf-enabled/*; then
            sed -i -e 's/^[^#]*deflate.mimetypes/#\0/' 88-tar1090.conf
            sed -i -e 's/^[^#]*deflate.mimetypes/#\0/' 95-tar1090-otherport.conf
        fi
    fi


    sed -i.orig -e "s?SOURCE_DIR?$srcdir?g" -e "s?SERVICE?${service}?g" tar1090.service

    cp -r -T html "$TMP"
    cp -r -T "$gpath/git-db/db" "$TMP/db-$DB_VERSION"
    sed -i -e "s/let databaseFolder = .*;/let databaseFolder = \"db-$DB_VERSION\";/" "$TMP/index.html"
    echo "{ \"tar1090Version\": \"$TAR_VERSION\", \"databaseVersion\": \"$DB_VERSION\" }" > "$TMP/version.json"
    echo "$TAR_VERSION" > "$TMP/version"

    # keep some stuff around
    mv "$html_path/config.js" "$TMP/config.js" 2>/dev/null || true
    mv "$html_path/upintheair.json" "$TMP/upintheair.json" 2>/dev/null || true

    # in case we have offlinemaps installed, modify config.js
    MAX_OFFLINE=""
    for i in {0..15}; do
        if [[ -d /usr/local/share/osm_tiles_offline/$i ]]; then
            MAX_OFFLINE=$i
        fi
    done
    if [[ -n "$MAX_OFFLINE" ]]; then
        if ! grep "$TMP/config.js" -e '^offlineMapDetail.*' -qs &>/dev/null; then
            echo "offlineMapDetail=$MAX_OFFLINE;" >> "$TMP/config.js"
        else
            sed -i -e "s/^offlineMapDetail.*/offlineMapDetail=$MAX_OFFLINE;/" "$TMP/config.js"
        fi
    fi

    cp "$ipath/customIcon.png" "$TMP/images/tar1090-favicon.png" &>/dev/null || true

    # bust cache for all css and js files

    dir=$(pwd)
    cd "$TMP"

    sed -i -e "s/tar1090 on github/tar1090 on github (${TAR_VERSION})/" index.html

    "$gpath/git/cachebust.sh" "$gpath/git/cachebust.list" "$TMP"

    rm -rf "$html_path"
    mv "$TMP" "$html_path"

    cd "$dir"

    cp nginx.conf "$ipath/nginx-${service}.conf"

    if [[ $lighttpd == yes ]]; then
        # clean up broken symlinks in conf-enabled ...
        for link in /etc/lighttpd/conf-enabled/*; do [[ -e "$link" ]] || rm -f "$link"; done
        if [[ "$otherport" != "done" ]]; then
            cp 95-tar1090-otherport.conf /etc/lighttpd/conf-available/
            ln -f -s /etc/lighttpd/conf-available/95-tar1090-otherport.conf /etc/lighttpd/conf-enabled/95-tar1090-otherport.conf
            otherport="done"
            if [ -f /etc/lighttpd/conf.d/69-skybup.conf ]; then
                mv /etc/lighttpd/conf-enabled/95-tar1090-otherport.conf /etc/lighttpd/conf-enabled/68-tar1090-otherport.conf
            fi
        fi
        if [ -f /etc/lighttpd/conf.d/69-skybup.conf ] && [[ "$instance" == "webroot" ]]; then
            true
        elif [[ "$instance" == "webroot" ]]
        then
            cp 88-tar1090.conf /etc/lighttpd/conf-available/99-"${service}".conf
            ln -f -s /etc/lighttpd/conf-available/99-"${service}".conf /etc/lighttpd/conf-enabled/99-"${service}".conf
        else
            cp 88-tar1090.conf /etc/lighttpd/conf-available/88-"${service}".conf
            ln -f -s /etc/lighttpd/conf-available/88-"${service}".conf /etc/lighttpd/conf-enabled/88-"${service}".conf
            if [ -f /etc/lighttpd/conf.d/69-skybup.conf ]; then
                mv /etc/lighttpd/conf-enabled/88-"${service}".conf /etc/lighttpd/conf-enabled/66-"${service}".conf
            fi
        fi
    fi

    if useSystemd; then
        if [[ $changed == yes ]] || ! diff tar1090.service /lib/systemd/system/"${service}".service &>/dev/null
        then
            cp tar1090.service /lib/systemd/system/"${service}".service
            if systemctl enable "${service}"
            then
                echo "Restarting ${service} ..."
                systemctl restart "$service" || ! pgrep systemd
            else
                echo "${service}.service is masked, could not start it!"
            fi
        fi
    fi

    # restore sed modified configuration files
    mv 88-tar1090.conf.orig 88-tar1090.conf
    mv 95-tar1090-otherport.conf.orig 95-tar1090-otherport.conf
    mv nginx.conf.orig nginx.conf
    mv tar1090.service.orig tar1090.service
done < <(echo "$instances")

if [[ $lighttpd == yes ]] || [[ $nginx == yes ]]; then
    true
fi

