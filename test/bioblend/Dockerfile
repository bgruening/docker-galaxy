FROM alpine:3.17 as build

ENV BIOBLEND_VERSION=1.9.0 \
    TOX_ENV=py310 \
    BIOBLEND_GALAXY_API_KEY=fakekey \
    BIOBLEND_GALAXY_URL=http://galaxy \
    BIOBLEND_TEST_JOB_TIMEOUT="240" \
    GALAXY_VERSION=release_26.1 \
    UV_INSTALL_DIR=/usr/local/bin

ADD "https://github.com/galaxyproject/bioblend/archive/v$BIOBLEND_VERSION.zip" /src/bioblend.zip
RUN apk update && apk add bash curl python3-dev unzip \
    && curl -LsSf https://astral.sh/uv/install.sh | bash \
    && uv pip install --system pep8 tox \
    && cd /src \
    && unzip bioblend.zip && rm bioblend.zip \
    && mv "bioblend-$BIOBLEND_VERSION" bioblend \
    && cd bioblend \
    && uv pip install --system .

WORKDIR /src/bioblend

CMD /bin/sh -c "tox -e $TOX_ENV -- -k 'not test_upload_from_galaxy_filesystem and not test_get_datasets and not test_datasets_from_fs and not test_cancel_invocation and not test_run_step_actions'"

# library tests, needs share /tmp filesystem
# * test_upload_from_galaxy_filesystem
# * test_get_datasets
# * test_datasets_from_fs
