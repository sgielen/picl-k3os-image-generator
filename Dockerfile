FROM ubuntu:groovy-20200723

# The repository should be mounted at /app.
WORKDIR /app

RUN apt-get update && apt-get install -y \
    wget \
    parted \
    dosfstools \
    binutils \
    p7zip-full \
    sudo \
    xz-utils \
    jq \
    u-boot-tools \
 && rm -rf /var/lib/apt/lists/*

COPY build-image.sh /app/build-image.sh
COPY init.preinit /app/init.preinit
COPY init.resizefs /app/init.resizefs
COPY orangepipc2-boot.cmd /app/orangepipc2-boot.cmd

CMD /app/build-image.sh $TARGET
