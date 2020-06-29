# mikenye/tar1090

[`tar1090`](https://github.com/wiedehopf/tar1090) is an excellent tool by [wiedehopf](https://github.com/wiedehopf) that provides an improved [`dump1090-fa`](https://github.com/flightaware/dump1090) interface.

At the time of writing this README, it provides:

* Improved adjustable history
* Show All Tracks much faster than original with many planes
* Multiple Maps available
* Map can be dimmed/darkened
* Multiple aircraft can be selected
* Labels with the callsign can be switched on and off

This image:

* Receives Beast data from a provider such as `dump1090` or `readsb`
* Optionally, receives MLAT data from a provider such as `mlat-client`
* Provides the `tar1090` web interface.

It builds and runs on `linux/amd64`, `linux/arm/v7` and `linux/arm64` (see below).

## Supported tags and respective Dockerfiles

* `latest` should always contain the latest released versions of `readsb`, `tar1090` and `tar1090-db`. This image is built nightly from the `master` branch `Dockerfile` for all supported architectures.
* `development` (`master` branch, `Dockerfile`, `amd64` architecture only, built on commit, not recommended for production)
* Specific version tags are available if required, however these are not regularly updated. It is generally recommended to run latest.

## Multi Architecture Support

* `linux/amd64`: Built on Linux x86-64
* `linux/arm/v6`: Built on Odroid HC2 running ARMv7 32-bit
* `linux/arm/v7`: Built on Odroid HC2 running ARMv7 32-bit
* `linux/arm64`: Built on a Raspberry Pi 4 Model B running ARMv8 64-bit

## Prerequisites

You will need a source of Beast data. This could be an RPi running PiAware, the [`mikenye/piaware`](https://hub.docker.com/r/mikenye/piaware) image or [`mikenye/readsb`](https://hub.docker.com/r/mikenye/readsb).

Optionally, you will need a source of MLAT data. This could be:
* ['mikenye/adsbexchange`](https://hub.docker.com/r/mikenye/adsbexchange) image
* [`mikenye/piaware`](https://hub.docker.com/r/mikenye/piaware) image
* Basically anything running `mlat-client` listening for beast connections (ie: `--results beast,listen,30105`)

## Up-and-Running with `docker run`

```shell
docker run -d \
    --name=tar1090 \
    -p 8078:80 \
    -e TZ=<TIMEZONE> \
    -e BEASTHOST=<BEASTHOST> \
    -e MLATHOST=<MLATHOST> \
    -e LAT=xx.xxxxx \
    -e LONG=xx.xxxxx \
    mikenye/tar1090:latest
```

Replacing `TIMEZONE` with your timezone, `BEASTHOST` with the IP address of a host that can provide Beast data, and `MLATHOST` with the IP address of a host that can provide MLAT data.

For example:

```shell
docker run -d \
    --name=tar1090 \
    -p 8078:80 \
    -e TZ=Australia/Perth \
    -e BEASTHOST=readsb \
    -e MLATHOST=adsbx \
    -e LAT=-33.33333 \
    -e LONG=111.11111 \
    mikenye/tar1090:latest
```

You should now be able to browse to http://dockerhost:8078 to access the `tar1090` web interface.

## Up-and-Running with `docker-compose`

An example `docker-compose.xml` file is below:

```shell
version: '2.0'

networks:
  adsbnet:

services:

  tar1090:
    image: mikenye/tar1090:latest
    tty: true
    container_name: tar1090
    restart: always
    environment:
      - TZ=Australia/Perth
      - BEASTHOST=readsb
      - MLATHOST=adsbx
      - LAT=-33.33333
      - LONG=111.11111
    networks:
      - adsbnet
    ports:
      - 8078:80
```

You should now be able to browse to http://dockerhost:8078 to access the `tar1090` web interface.

## Up-and-Running with `docker-compose` including `mikenye/readsb`

An example `docker-compose.xml` file is below:

```shell
version: '2.0'

networks:
  adsbnet:

services:

  readsb:
    image: mikenye/readsb:latest
    tty: true
    container_name: readsb
    restart: always
    devices:
      - /dev/bus/usb/001/007:/dev/bus/usb/001/007
    ports:
      - 8079:80
    networks:
      - adsbnet
    command:
      - --dcfilter
      - --device-type=rtlsdr
      - --fix
      - --json-location-accuracy=2
      - --lat=-33.33333
      - --lon=111.11111
      - --metric
      - --modeac
      - --ppm=0
      - --net
      - --stats-every=3600
      - --quiet
      - --write-json=/run/readsb

  tar1090:
    image: mikenye/tar1090:latest
    tty: true
    container_name: tar1090
    restart: always
    environment:
      - TZ=Australia/Perth
      - BEASTHOST=readsb
      - LAT=-33.33333
      - LONG=111.11111
    networks:
      - adsbnet
    ports:
      - 8078:80
```

*Note*: the example above excludes `MLATHOST` as `readsb` alone cannot provide MLAT data. You'll need a feeder container for this.

For an explanation of the `mikenye/readsb` image's configuration, see that image's readme.

## Ports

### Outgoing

This container will try to connect to the `BEASTHOST` on TCP port `30005` by default. This can be changed by setting the `BEASTPORT` environment variable.

If `MLATHOST` is set, this container will try to connecto the `MLATHOST` on TCP port `30105` by default. This can be changed to setting the `MLATPORT` environment variable.

### Incoming

This container accepts HTTP connections on TCP port `80` by default. You can change this with the container's port mapping. In the examples above, this has been changed to `8078`.

## Runtime Environment Variables

| Environment Variable | Purpose | Default |
|----------------------|---------|---------|
| `BEASTHOST` | Required. IP/Hostname of a Mode-S/Beast provider (`dump1090`/`readsb`) | |
| `BEASTPORT` | Optional. TCP port number of Mode-S/Beast provider (`dump1090`/`readsb`) | `30005` |
| `LAT` | Optional. The latitude of your antenna | |
| `LONG` | Optional. The longitude of your antenna | |
| `MLATHOST` | Optional. IP/Hostname of an MLAT provider (`mlat-client`) | |
| `MLATPORT` | Optional. TCP port number of an MLAT provider (`mlat-client`) | 30105 |
| `TZ` | Optional. Your local timezone in [TZ-database-name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) format | |
| `HEYWHATSTHAT_PANORAMA_ID` | Optional. Your `heywhatsthat.com` panorama ID. See <https://github.com/wiedehopf/tar1090#heywhatsthatcom-range-outline>. | |
| `HTTP_ACCESS_LOG` | Optional. Set to `true` to display HTTP server access logs. | `false` |
| `HTTP_ERROR_LOG` | Optional. Set to `false` to hide HTTP server error logs. | `true` |

## Paths

No paths need to be mapped through to persistent storage. However, if you don't want to lose your aircraft tracks/history on container restart, you can optionally map these paths:

| Path | Purpose |
|------|---------|
| `/var/globe_history` | Holds past 24 hours of heatmap data |

## Logging

All logs are to the container's stdout and can be viewed with `docker logs [-f] container`.

## Getting help

Please feel free to [open an issue on the project's GitHub](https://github.com/mikenye/docker-tar1090/issues).

## Changelog

### 20200630

* Add `HTTP_ACCESS_LOG` & `HTTP_ERROR_LOG`. Change `readsb` build process for greater compatibility.

### 20200627

* Add `tar1090`'s new `heatmap` functionality

### 20200622

* Add `HEYWHATSTHAT_PANORAMA_ID` environment variable for range outline

### 20200508

* Add `linux/arm/v6` architecture support

### 20200506

* Add `MLATHOST` and `MLATPORT` options

### 20200331

* Original Image
