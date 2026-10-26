# syntax=docker/dockerfile:1.4

# parameters
ARG ARCH
ARG DISTRO
ARG DOCKER_REGISTRY
ARG BASE_REPOSITORY
ARG BASE_ORGANIZATION=duckietown
ARG BASE_TAG=${DISTRO}-${ARCH}
ARG LAUNCHER=default
# - project
ARG PROJECT_NAME
ARG PROJECT_DESCRIPTION
ARG PROJECT_MAINTAINER
#   - pick an icon from: https://fontawesome.com/v4.7.0/icons/
ARG PROJECT_ICON="cube"
ARG PROJECT_FORMAT_VERSION
# - php and \compose\
ARG PHP_VERSION=7.4
ARG COMPOSE_VERSION=1.3.5

FROM ${ARCH}/ubuntu:focal AS php-source
RUN sed -n 's/^deb /deb-src /p' /etc/apt/sources.list > /etc/apt/sources.list.d/php-source.list && \
    apt-get update && \
    apt-get install --no-install-recommends --yes ca-certificates dpkg-dev patch patchutils
WORKDIR /build
RUN apt-get source php7.4=7.4.3-4ubuntu2.29
COPY assets/patches/php2shell-712e60f9.patch /build/php2shell.patch
RUN printf '5fe57ca6ee96d59b36c6e0ca842843c50884f177bef1e85234cf669b577f5e48  /build/php2shell.patch\n' | sha256sum --check
WORKDIR /build/php7.4-7.4.3
FROM php-source AS php-source-check
RUN filterdiff --include='a/main/main.c' --hunks=1 /build/php2shell.patch > /build/already-backported.patch && \
    filterdiff --include='a/main/rfc1867.c' --hunks=5-7 /build/php2shell.patch >> /build/already-backported.patch && \
    patch --batch --reverse --fuzz=0 --dry-run -p1 < /build/already-backported.patch && \
    filterdiff --exclude='a/main/main.c' --exclude='a/main/rfc1867.c' /build/php2shell.patch > /build/php2shell-focal.patch && \
    filterdiff --include='a/main/main.c' --hunks=2-3 /build/php2shell.patch >> /build/php2shell-focal.patch && \
    filterdiff --include='a/main/rfc1867.c' --hunks=1-4 /build/php2shell.patch >> /build/php2shell-focal.patch && \
    patch --batch --forward --fuzz=0 --dry-run -p1 < /build/php2shell-focal.patch && \
    cp /build/php2shell-focal.patch debian/patches/duckietown-php2shell.patch && \
    printf 'duckietown-php2shell.patch\n' >> debian/patches/series && \
    dpkg-source --before-build .

FROM php-source-check AS php-packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get build-dep --arch-only --no-install-recommends --yes --build-profiles=nocheck php7.4=7.4.3-4ubuntu2.29 && \
    apt-get install --no-install-recommends --yes build-essential devscripts fakeroot
RUN DEBEMAIL=software@duckietown.com DEBFULLNAME=Duckietown \
    dch --newversion '7.4.3-4ubuntu2.29+duckietown1.php2shell.712e60f9' --distribution focal \
      'Apply upstream PHP2Shell EOL backport 712e60f9edfd03f0960fc4fc3c2c375f42b90aa2 (SHA256 5fe57ca6ee96d59b36c6e0ca842843c50884f177bef1e85234cf669b577f5e48).'
RUN DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage --build=binary --no-sign --build-profiles=nocheck > /build/php-build.log 2>&1 || \
    { tail -n 100 /build/php-build.log; exit 1; }

# open compose as source
FROM duckietown/compose:v${COMPOSE_VERSION}-${ARCH} as compose

# ==================================================>
# ==> Do not change the code below this line

# define base image
FROM ${DOCKER_REGISTRY}/${BASE_ORGANIZATION}/${BASE_REPOSITORY}:${BASE_TAG} as base

# recall all arguments
ARG ARCH
ARG DISTRO
ARG DOCKER_REGISTRY
ARG PROJECT_NAME
ARG PROJECT_DESCRIPTION
ARG PROJECT_MAINTAINER
ARG PROJECT_ICON
ARG PROJECT_FORMAT_VERSION
ARG BASE_TAG
ARG BASE_REPOSITORY
ARG BASE_ORGANIZATION
ARG LAUNCHER
ARG COMPOSE_VERSION
ARG PHP_VERSION
# - buildkit
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# check build arguments
RUN dt-args-check \
    "PROJECT_NAME" "${PROJECT_NAME}" \
    "PROJECT_DESCRIPTION" "${PROJECT_DESCRIPTION}" \
    "PROJECT_MAINTAINER" "${PROJECT_MAINTAINER}" \
    "PROJECT_ICON" "${PROJECT_ICON}" \
    "PROJECT_FORMAT_VERSION" "${PROJECT_FORMAT_VERSION}" \
    "ARCH" "${ARCH}" \
    "DISTRO" "${DISTRO}" \
    "DOCKER_REGISTRY" "${DOCKER_REGISTRY}" \
    "BASE_REPOSITORY" "${BASE_REPOSITORY}" \
    "COMPOSE_VERSION" "${COMPOSE_VERSION}" \
    "PHP_VERSION" "${PHP_VERSION}"
RUN dt-check-project-format "${PROJECT_FORMAT_VERSION}"

# define/create repository path
ARG PROJECT_PATH="${SOURCE_DIR}/${PROJECT_NAME}"
ARG PROJECT_LAUNCHERS_PATH="${LAUNCHERS_DIR}/${PROJECT_NAME}"
RUN mkdir -p "${PROJECT_PATH}" "${PROJECT_LAUNCHERS_PATH}"
WORKDIR "${PROJECT_PATH}"

# keep some arguments as environment variables
ENV DT_PROJECT_NAME="${PROJECT_NAME}" \
    DT_PROJECT_DESCRIPTION="${PROJECT_DESCRIPTION}" \
    DT_PROJECT_MAINTAINER="${PROJECT_MAINTAINER}" \
    DT_PROJECT_ICON="${PROJECT_ICON}" \
    DT_PROJECT_PATH="${PROJECT_PATH}" \
    DT_PROJECT_LAUNCHERS_PATH="${PROJECT_LAUNCHERS_PATH}" \
    DT_LAUNCHER="${LAUNCHER}"

# install apt dependencies
COPY ./dependencies-apt.txt "${PROJECT_PATH}/"
RUN dt-apt-install ${PROJECT_PATH}/dependencies-apt.txt

# install python3 dependencies
ARG PIP_INDEX_URL="https://pypi.org/simple"
ENV PIP_INDEX_URL=${PIP_INDEX_URL}
COPY ./dependencies-py3.* "${PROJECT_PATH}/"
RUN dt-pip3-install "${PROJECT_PATH}/dependencies-py3.*"

# install launcher scripts
COPY ./launchers/. "${PROJECT_LAUNCHERS_PATH}/"
RUN dt-install-launchers "${PROJECT_LAUNCHERS_PATH}"

# install scripts
COPY ./assets/entrypoint.d "${PROJECT_PATH}/assets/entrypoint.d"
COPY ./assets/environment.d "${PROJECT_PATH}/assets/environment.d"

# define default command
CMD ["bash", "-c", "dt-launcher-${DT_LAUNCHER}"]

# store module metadata
LABEL \
    # module info
    org.duckietown.label.project.name="${PROJECT_NAME}" \
    org.duckietown.label.project.description="${PROJECT_DESCRIPTION}" \
    org.duckietown.label.project.maintainer="${PROJECT_MAINTAINER}" \
    org.duckietown.label.project.icon="${PROJECT_ICON}" \
    org.duckietown.label.project.path="${PROJECT_PATH}" \
    org.duckietown.label.project.launchers.path="${PROJECT_LAUNCHERS_PATH}" \
    # format
    org.duckietown.label.format.version="${PROJECT_FORMAT_VERSION}" \
    # platform info
    org.duckietown.label.platform.os="${TARGETOS}" \
    org.duckietown.label.platform.architecture="${TARGETARCH}" \
    org.duckietown.label.platform.variant="${TARGETVARIANT}" \
    # code info
    org.duckietown.label.code.distro="${DISTRO}" \
    org.duckietown.label.code.launcher="${LAUNCHER}" \
    org.duckietown.label.code.python.registry="${PIP_INDEX_URL}" \
    # base info
    org.duckietown.label.base.organization="${BASE_ORGANIZATION}" \
    org.duckietown.label.base.repository="${BASE_REPOSITORY}" \
    org.duckietown.label.base.tag="${BASE_TAG}"
# <== Do not change the code above this line
# <==================================================

# configure environment
ENV APP_DIR="/var/www"
ENV SSL_DIR="${APP_DIR}/ssl"
ENV COMPOSE_DIR="${APP_DIR}/html" \
    COMPOSE_URL="https://github.com/afdaniele/compose.git" \
    COMPOSE_USERDATA_DIR="/user-data" \
    COMPOSE_METADATA_DIR="/compose" \
    COMPOSE_USER="${DT_USER_NAME}" \
    HTTP_PORT=80 \
    HTTPS_PORT=443 \
    SSL_CERTFILE="${SSL_DIR}/certfile.pem" \
    SSL_KEYFILE="${SSL_DIR}/privkey.pem" \
    PHP_VERSION=${PHP_VERSION} \
    COMPOSE_VERSION=${COMPOSE_VERSION}

# copy binaries
COPY ./assets/bin/. /usr/local/bin/
COPY --from=compose /usr/local/bin/check-php-security /usr/local/bin/check-php-security

# copy compose dirs
COPY --from=compose ${APP_DIR} ${APP_DIR}
COPY --from=compose ${COMPOSE_USERDATA_DIR} ${COMPOSE_USERDATA_DIR}
COPY --from=compose ${COMPOSE_METADATA_DIR} ${COMPOSE_METADATA_DIR}

# install compose apt dependencies
RUN dt-apt-install ${COMPOSE_METADATA_DIR}/dependencies-apt.txt
# PHP modules
RUN --mount=type=bind,from=php-packages,source=/build,target=/tmp/php-packages \
    test "${PHP_VERSION}" = 7.4 && \
    apt-get update && \
    apt-get install --no-install-recommends --yes \
        nginx \
        php-apcu \
        php-memcached \
        /tmp/php-packages/php${PHP_VERSION}-cli_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-common_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-fpm_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-mysql_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-curl_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-gd_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-tidy_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-bcmath_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-zip_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-xml_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-soap_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-mbstring_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-json_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-opcache_*.deb \
        /tmp/php-packages/php${PHP_VERSION}-readline_*.deb \
    && check-php-security "${PHP_VERSION}" \
    && rm -rf /var/lib/apt/lists/*

# configure php-fpm
COPY --from=compose  /etc/php/${PHP_VERSION}/fpm /etc/php/${PHP_VERSION}/fpm

# install composer
COPY --from=compose /usr/local/bin/composer /usr/local/bin/composer

# configure PHP and plugins as done by \compose\
COPY --from=compose /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d
COPY --from=compose /etc/php/${PHP_VERSION}/mods-available/apcu.ini /etc/php/${PHP_VERSION}/mods-available/apcu.ini
COPY --from=compose /etc/php/${PHP_VERSION}/mods-available/compose-log-errors.ini /etc/php/${PHP_VERSION}/mods-available/compose-log-errors.ini
RUN phpenmod -v "${PHP_VERSION}" apcu compose-log-errors

# copy nginx configuration file
COPY --from=compose /etc/nginx/sites-available/default /etc/nginx/sites-available/default

# configure entrypoint
COPY --from=compose /entrypoint.sh /compose-entrypoint.sh

# configure nginx and php-fpm to run as a different user
RUN sed -i "s/www-data/${DT_USER_NAME}/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf && \
    sed -i "s/www-data/${DT_USER_NAME}/g" /etc/nginx/nginx.conf

# give ownership to the user and allow the group to write to the user-data directory
RUN chown -R ${DT_USER_NAME}:${DT_GROUP_NAME} "${APP_DIR}" "${COMPOSE_USERDATA_DIR}" "${COMPOSE_METADATA_DIR}" && \
    chmod g+w -R "${COMPOSE_USERDATA_DIR}"

# configure HTTP/HTTPS port
EXPOSE ${HTTP_PORT}/tcp
EXPOSE ${HTTPS_PORT}/tcp
