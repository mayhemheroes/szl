FROM --platform=linux/amd64 ubuntu:20.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential git meson libz-dev libcurl4-gnutls-dev libarchive-dev libssl-dev libffi-dev pkg-config


ADD . /repo
WORKDIR /repo
RUN meson build
WORKDIR /repo/build
RUN ninja
RUN ninja install

RUN mkdir -p /deps
RUN ldd /repo/build/src/szl | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /repo/build/src/szl /repo/build/src/szl
ENV LD_LIBRARY_PATH=/deps
