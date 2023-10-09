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
ARG PHP_VERSION=7.0
ARG COMPOSE_VERSION=1.3.1

# open compose as source
FROM docker.io/afdaniele/compose:v${COMPOSE_VERSION}-${ARCH} as compose

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
ARG PHP_VERSION
ARG COMPOSE_VERSION
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
    "BASE_REPOSITORY" "${BASE_REPOSITORY}"
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
    HTTP_PORT=80 \
    HTTPS_PORT=443 \
    SSL_CERTFILE="${SSL_DIR}/certfile.pem" \
    SSL_KEYFILE="${SSL_DIR}/privkey.pem" \
    PHP_VERSION=${PHP_VERSION} \
    COMPOSE_VERSION=${COMPOSE_VERSION}

# copy compose dirs
COPY --from=compose ${APP_DIR} ${APP_DIR}
COPY --from=compose ${COMPOSE_USERDATA_DIR} ${COMPOSE_USERDATA_DIR}
COPY --from=compose ${COMPOSE_METADATA_DIR} ${COMPOSE_METADATA_DIR}

# install compose apt dependencies
RUN dt-apt-install ${COMPOSE_METADATA_DIR}/dependencies-apt.txt

# PHP modules
RUN add-apt-repository -y ppa:ondrej/php && \
    add-apt-repository -y ppa:nginx/stable && \
    apt-get install --no-install-recommends --yes \
        nginx \
        php7.0-apcu \
        php7.0-cli \
        php7.0-fpm \
        php7.0-mysql \
        php7.0-curl \
        php7.0-memcached \
        php7.0-gd \
        php7.0-mcrypt \
        php7.0-tidy \
        php7.0-bcmath \
        php7.0-zip \
        php7.0-xml \
        php7.0-soap \
        php7.0-mbstring

# configure php-fpm
COPY --from=compose  /etc/php/7.0/fpm /etc/php/7.0/fpm

# install composer
COPY --from=compose /usr/local/bin/composer /usr/local/bin/composer

# configure PHP and plugins as done by \compose\
COPY --from=compose /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d

# copy nginx configuration file
COPY --from=compose /etc/nginx/sites-available/default /etc/nginx/sites-available/default

# configure entrypoint
COPY --from=compose /entrypoint.sh /compose-entrypoint.sh

# give ownership to www-data
RUN chown -R www-data:www-data "${APP_DIR}" "${COMPOSE_USERDATA_DIR}" "${COMPOSE_METADATA_DIR}"

# configure health check
HEALTHCHECK \
  --interval=30s \
  --timeout=8s \
  CMD \
    curl --fail "http://localhost:${HTTP_PORT}/script.php?script=healthcheck" > /dev/null 2>&1 \
    || \
    exit 1

# configure HTTP/HTTPS port
EXPOSE ${HTTP_PORT}/tcp
EXPOSE ${HTTPS_PORT}/tcp
