ARG CITYDB_IMAGE=3dcitydb/3dcitydb-pg:5-alpine@sha256:d786d67bc0641cc11c8676c816c4b76da7a769bb47c3c446f67e1be9514010ec
FROM ${CITYDB_IMAGE}

# ogr_fdw v1.1.9, pinned to its release commit. Build against this image's
# PostgreSQL headers; distro PostgreSQL packages use different installation paths.
ARG OGR_FDW_COMMIT=adaa6fc0ca1da8847f216f76899df3f731878e83
RUN set -eux; \
    apk add --no-cache --virtual .ogr-fdw-builddeps build-base gdal-dev curl; \
    mkdir -p /tmp/ogr-fdw; \
    curl --fail --location --retry 3 \
      "https://codeload.github.com/pramsey/pgsql-ogr-fdw/tar.gz/${OGR_FDW_COMMIT}" \
      -o /tmp/ogr-fdw.tar.gz; \
    tar -xzf /tmp/ogr-fdw.tar.gz --strip-components=1 -C /tmp/ogr-fdw; \
    make -C /tmp/ogr-fdw with_llvm=no; \
    make -C /tmp/ogr-fdw with_llvm=no install; \
    apk add --no-cache gdal; \
    apk del .ogr-fdw-builddeps; \
    rm -rf /tmp/ogr-fdw /tmp/ogr-fdw.tar.gz; \
    test -f "$(pg_config --sharedir)/extension/postgres_fdw.control"; \
    test -f "$(pg_config --sharedir)/extension/ogr_fdw.control"; \
    ogr_fdw_info -f

# HTTP v1.7.0: retrieve source metadata directly from SQL.
ARG HTTP_COMMIT=fbea6fe46c9e1db5a18103606ec00a9809e91d11
RUN set -eux; \
    apk add --no-cache --virtual .http-builddeps build-base curl-dev; \
    apk add --no-cache curl; \
    mkdir -p /tmp/pgsql-http; \
    curl --fail --location --retry 3 \
      "https://codeload.github.com/pramsey/pgsql-http/tar.gz/${HTTP_COMMIT}" \
      -o /tmp/pgsql-http.tar.gz; \
    tar -xzf /tmp/pgsql-http.tar.gz --strip-components=1 -C /tmp/pgsql-http; \
    make -C /tmp/pgsql-http with_llvm=no; \
    make -C /tmp/pgsql-http with_llvm=no install; \
    apk del .http-builddeps; \
    rm -rf /tmp/pgsql-http /tmp/pgsql-http.tar.gz; \
    test -f "$(pg_config --sharedir)/extension/http.control"

# Keep upstream initialization scripts and run the mounted UTT folder after them.
# Non-executable so PostgreSQL sources the hook with its init helpers available.
COPY --chmod=644 900-utt-init.sh /docker-entrypoint-initdb.d/900-utt-init.sh

LABEL org.opencontainers.image.title="UrbanTwin-Toolbox Database" \
      org.opencontainers.image.description="UTTDB image based on 3DCityDB, with PostgreSQL/PostGIS and foreign data wrappers." \
      utt.ogr-fdw.version="1.1.9"
