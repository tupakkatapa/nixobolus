FROM docker.io/nixos/nix

ARG hostname=ethobolus
ENV BUILD_ME=$hostname

ARG system=x86_64-linux
ENV SYSTEM_ARCH=$system

RUN echo "extra-experimental-features = flakes nix-command" > /etc/nix/nix.conf \
    && echo "accept-flake-config = true" >> /etc/nix/nix.conf

CMD nix develop && nix build .#nixobolus.$SYSTEM_ARCH.$BUILD_ME \
    && rsync -L -r result out && unlink result
