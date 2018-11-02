FROM vmware/photon

ENV GOVERSION=1.9.2
ENV PATH=$PATH:/usr/local/go/bin

RUN set -eux; \
    tdnf install -y make tar gzip python2 python-pip sed git diff \
    gawk docker gptfdisk e2fsprogs grub2 parted xz docker jq cpio;

RUN set -eux; \
    curl -L'#' -k https://storage.googleapis.com/golang/go$GOVERSION.linux-amd64.tar.gz | tar xzf - -C /usr/local;

COPY ./build/ /build/
COPY ./bin/ovfenv ./bin/dcui ./bin/rpctool /build/bin/

WORKDIR /build/

RUN set -eux; \
    mv container/qemu-img.xz /usr/bin/qemu-img.xz; \
    cd /usr/bin/; \
    xz -d qemu-img.xz; \
    chmod +x qemu-img;

ENTRYPOINT ["/build/bootable/build-main.sh", "-m", "/build/out/ova-manifest.yml", "-r", "/build/out"]

CMD ["-c"]
