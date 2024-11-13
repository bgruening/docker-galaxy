FROM ubuntu:22.04 AS sge_master

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
    && apt-get install -y wget gridengine-exec gridengine-client \
    # need to run this before gridengine-master installation (https://bugs.launchpad.net/ubuntu/+source/gridengine/+bug/1774302)
    && wget http://ftp.debian.org/debian/pool/main/g/gridengine/gridengine-client_8.1.9+dfsg-10+b1_amd64.deb \
    && dpkg -x gridengine-client_8.1.9+dfsg-10+b1_amd64.deb ge-client \
    && cp ge-client/usr/lib/gridengine/spooldefaults.bin /usr/lib/gridengine/ \
    && cp ge-client/usr/lib/gridengine/libspool*.so /usr/lib/gridengine/ \
    && rm -rf gridengine-client_8.1.9+dfsg-10+b1_amd64.deb ge-client \
    && apt purge -y wget && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN apt-get update -qq \
    && apt-get install -y gridengine-master \
    && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# dummy user account
RUN useradd -m dummy \
    && echo "dummy:dummy" | chpasswd

ADD --chmod=755 setup_gridengine.sh /usr/local/bin/setup_gridengine.sh


FROM python:3.10.15 AS sge_bioblend_test
RUN pip install bioblend==1.3.0
