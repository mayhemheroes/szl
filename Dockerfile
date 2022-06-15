FROM --platform=linux/amd64 ubuntu:20.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential git meson libz-dev libcurl4-gnutls-dev libarchive-dev libssl-dev libffi-dev pkg-config


ADD . /repo
WORKDIR /repo
RUN meson build
WORKDIR /repo/build
RUN ninja
RUN ninja install

