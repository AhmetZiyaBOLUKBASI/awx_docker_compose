### This file is generated from
### tools/ansible/roles/dockerfile/templates/Dockerfile.j2
###
### DO NOT EDIT
###

# Build container
FROM quay.io/centos/centos:stream9 as builder

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV AWX_LOGGING_MODE stdout


USER root

# Install build dependencies
RUN dnf -y update && dnf install -y 'dnf-command(config-manager)' && \
    dnf config-manager --set-enabled crb && \
    dnf -y install \
    gcc \
    gcc-c++ \
    git-core \
    gettext \
    glibc-langpack-en \
    libffi-devel \
    libtool-ltdl-devel \
    make \
    nodejs \
    nss \
    openldap-devel \
    patch \
    postgresql \
    postgresql-devel \
    python3-devel \
    python3-pip \
    python3-psycopg2 \
    python3-setuptools \
    swig \
    unzip \
    xmlsec1-devel \
    xmlsec1-openssl-devel

RUN pip3 install virtualenv build


# Install & build requirements
ADD Makefile /tmp/Makefile
RUN mkdir /tmp/requirements
ADD requirements/requirements.txt \
    requirements/requirements_tower_uninstall.txt \
    requirements/requirements_git.txt \
    /tmp/requirements/

RUN cd /tmp && make requirements_awx

ARG VERSION
ARG SETUPTOOLS_SCM_PRETEND_VERSION
ARG HEADLESS

ADD requirements/requirements_dev.txt /tmp/requirements
RUN cd /tmp && make requirements_awx_dev

# Final container(s)
FROM quay.io/centos/centos:stream9

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV AWX_LOGGING_MODE stdout

USER root

# Install runtime requirements
RUN dnf -y update && dnf install -y 'dnf-command(config-manager)' && \
    dnf config-manager --set-enabled crb && \
    dnf -y install acl \
    git-core \
    git-lfs \
    glibc-langpack-en \
    krb5-workstation \
    nginx \
    postgresql \
    python3-devel \
    python3-libselinux \
    python3-pip \
    python3-psycopg2 \
    python3-setuptools \
    rsync \
    "rsyslog >= 8.1911.0" \
    subversion \
    sudo \
    vim-minimal \
    which \
    unzip \
    xmlsec1-openssl && \
    dnf -y clean all

RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && \
    ./get_helm.sh

RUN pip3 install virtualenv supervisor dumb-init

RUN rm -rf /root/.cache && rm -rf /tmp/*

# Install development/test requirements
RUN dnf -y install \
    crun \
    gdb \
    gtk3 \
    gettext \
    hostname \
    procps \
    alsa-lib \
    libX11-xcb \
    libXScrnSaver \
    iproute \
    strace \
    vim \
    nmap-ncat \
    libpq-devel \
    nodejs \
    nss \
    make \
    patch \
    socat \
    tmux \
    wget \
    diffutils \
    unzip && \
    npm install -g n && n 16.13.1 && npm install -g npm@8.5.0 && dnf remove -y nodejs

RUN pip3 install black git+https://github.com/coderanger/supervisor-stdout setuptools-scm

# This package randomly fails to download.
# It is nice to have in the dev env, but not necessary.
# Add it back to the list above if the repo ever straighten up.
RUN dnf --enablerepo=baseos-debug -y install python3-debuginfo || :

RUN dnf install -y epel-next-release && dnf install -y inotify-tools && dnf remove -y epel-next-release

# Copy app from builder
COPY --from=builder /var/lib/awx /var/lib/awx

RUN ln -s /var/lib/awx/venv/awx/bin/awx-manage /usr/bin/awx-manage

COPY --from=quay.io/ansible/receptor:devel /usr/bin/receptor /usr/bin/receptor

RUN openssl req -nodes -newkey rsa:2048 -keyout /etc/nginx/nginx.key -out /etc/nginx/nginx.csr \
        -subj "/C=US/ST=North Carolina/L=Durham/O=Ansible/OU=AWX Development/CN=awx.localhost" && \
    openssl x509 -req -days 365 -in /etc/nginx/nginx.csr -signkey /etc/nginx/nginx.key -out /etc/nginx/nginx.crt && \
    chmod 640 /etc/nginx/nginx.{csr,key,crt}

RUN dnf install -y podman && rpm --restore shadow-utils 2>/dev/null

# chmod containers.conf and adjust storage.conf to enable Fuse storage.
RUN sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' -e 's|^mountopt[[:space:]]*=.*$|mountopt = "nodev,fsync=0"|g' /etc/containers/storage.conf

ENV _CONTAINERS_USERNS_CONFIGURED=""

# Ensure we must use fully qualified image names
# This prevents podman prompt that hangs when trying to pull unqualified images
RUN mkdir -p /etc/containers/registries.conf.d/ && echo "unqualified-search-registries = []" >> /etc/containers/registries.conf.d/force-fully-qualified-images.conf && chmod 644 /etc/containers/registries.conf.d/force-fully-qualified-images.conf

# Create default awx rsyslog config
ADD tools/ansible/roles/dockerfile/files/rsyslog.conf /var/lib/awx/rsyslog/rsyslog.conf
ADD tools/ansible/roles/dockerfile/files/wait-for-migrations /usr/local/bin/wait-for-migrations
ADD tools/ansible/roles/dockerfile/files/stop-supervisor /usr/local/bin/stop-supervisor

## File mappings
ADD tools/docker-compose/launch_awx.sh /usr/bin/launch_awx.sh
ADD tools/docker-compose/nginx.conf /etc/nginx/nginx.conf
ADD tools/docker-compose/nginx.vh.default.conf /etc/nginx/conf.d/nginx.vh.default.conf
ADD tools/docker-compose/start_tests.sh /start_tests.sh
ADD tools/docker-compose/bootstrap_development.sh /usr/bin/bootstrap_development.sh
ADD tools/docker-compose/entrypoint.sh /entrypoint.sh
ADD tools/scripts/config-watcher /usr/bin/config-watcher
ADD https://raw.githubusercontent.com/containers/libpod/master/contrib/podmanimage/stable/containers.conf /etc/containers/containers.conf
ADD https://raw.githubusercontent.com/containers/libpod/master/contrib/podmanimage/stable/podman-containers.conf /var/lib/awx/.config/containers/containers.conf
ADD tools/docker-compose/awx.egg-link /tmp/awx.egg-link
ADD tools/docker-compose/awx-manage /usr/local/bin/awx-manage
ADD tools/scripts/awx-python /usr/bin/awx-python

# Pre-create things we need to access
RUN for dir in \
      /var/lib/awx \
      /var/lib/awx/rsyslog \
      /var/lib/awx/rsyslog/conf.d \
      /var/lib/awx/.local/share/containers/storage \
      /var/run/awx-rsyslog \
      /var/log/nginx \
      /var/lib/postgresql \
      /var/run/supervisor \
      /var/run/awx-receptor \
      /var/lib/nginx ; \
    do mkdir -m 0775 -p $dir ; chmod g+rwx $dir ; chgrp root $dir ; done && \
    for file in \
      /etc/subuid \
      /etc/subgid \
      /etc/group \
      /etc/passwd \
      /var/lib/awx/rsyslog/rsyslog.conf ; \
    do touch $file ; chmod g+rw $file ; chgrp root $file ; done

RUN for dir in \
      /etc/containers \
      /var/lib/awx/.config/containers \
      /var/lib/awx/.config/cni \
      /var/lib/awx/.local \
      /var/lib/awx/venv \
      /var/lib/awx/venv/awx/bin \
      /var/lib/awx/venv/awx/lib/python3.9 \
      /var/lib/awx/venv/awx/lib/python3.9/site-packages \
      /var/lib/awx/projects \
      /var/lib/awx/rsyslog \
      /var/run/awx-rsyslog \
      /.ansible \
      /var/lib/shared/overlay-images \
      /var/lib/shared/overlay-layers \
      /var/lib/shared/vfs-images \
      /var/lib/shared/vfs-layers \
      /var/lib/awx/vendor ; \
    do mkdir -m 0775 -p $dir ; chmod g+rwx $dir ; chgrp root $dir ; done && \
    for file in \
      /etc/containers/containers.conf \
      /var/lib/awx/.config/containers/containers.conf \
      /var/lib/shared/overlay-images/images.lock \
      /var/lib/shared/overlay-layers/layers.lock \
      /var/lib/shared/vfs-images/images.lock \
      /var/lib/shared/vfs-layers/layers.lock \
      /var/run/nginx.pid \
      /var/lib/awx/venv/awx/lib/python3.9/site-packages/awx.egg-link ; \
    do touch $file ; chmod g+rw $file ; done


ENV HOME="/var/lib/awx"
ENV PATH="/usr/pgsql-12/bin:${PATH}"

ENV PATH="/var/lib/awx/venv/awx/bin/:${PATH}"

EXPOSE 8043 8013 8080 22

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
