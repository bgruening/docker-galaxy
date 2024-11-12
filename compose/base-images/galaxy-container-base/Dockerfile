FROM buildpack-deps:20.04  as build_singularity

COPY ./files/common_cleanup.sh /usr/bin/common_cleanup.sh

# Install Go (only needed for building singularity)
ENV GO_VERSION=1.13
RUN apt update && apt install --no-install-recommends cryptsetup-bin uuid-dev -y \
    && wget https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz \
    && tar -C /usr/local -xzvf go${GO_VERSION}.linux-amd64.tar.gz \
    && rm go${GO_VERSION}.linux-amd64.tar.gz \
    && /usr/bin/common_cleanup.sh

ENV PATH=/usr/local/go/bin:${PATH}
ENV SINGULARITY_VERSION=3.5.3
RUN wget https://github.com/singularityware/singularity/releases/download/v${SINGULARITY_VERSION}/singularity-${SINGULARITY_VERSION}.tar.gz \
    && tar -xzf singularity-${SINGULARITY_VERSION}.tar.gz \
    && cd singularity \
    && ./mconfig \
    && make -C builddir \
    && /usr/bin/common_cleanup.sh


# --- Final image ---
FROM ubuntu:20.04 as final

COPY ./files/common_cleanup.sh /usr/bin/common_cleanup.sh

# Base dependencies
RUN apt update && apt install --no-install-recommends ca-certificates python3-distutils squashfs-tools -y \
    && /usr/bin/common_cleanup.sh

# Install Docker
RUN apt update \
    && apt install --no-install-recommends docker.io -y \
    && /usr/bin/common_cleanup.sh

# Install Singularity
COPY --from=build_singularity /singularity /singularity
RUN apt update && apt install --no-install-recommends make -y \
    && make -C /singularity/builddir install \
    && apt remove make -y \
    && rm -rf /singularity \
    && sed -e '/bind path = \/etc\/localtime/s/^/#/g' -i /usr/local/etc/singularity/singularity.conf \
    && /usr/bin/common_cleanup.sh
