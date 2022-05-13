# Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder

## Install build dependencies.
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y vim less man wget tar git gzip unzip make cmake software-properties-common curl
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y git gcc meson zlib1g-dev libcurl4-gnutls-dev libarchive-dev libssl-dev libffi-dev pkg-config


ADD . /repo
WORKDIR /repo
RUN meson build
WORKDIR /repo/build
RUN ninja
RUN ninja install
