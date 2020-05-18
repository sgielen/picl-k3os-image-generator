FROM ubuntu:latest

# Create app directory
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

RUN apt-get update && apt-get install -y \
    wget \
    parted \
    kpartx \
    dosfstools \
    binutils \
    p7zip-full \
    sudo \
    xz-utils

COPY ./ /usr/src/app

CMD ./build-image.sh $TARGET