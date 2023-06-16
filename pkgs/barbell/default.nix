{ pkgs ? import <nixpkgs> { } }:

let
  name = "barbell";
  src = pkgs.fetchFromGitHub {
    # https://github.com/jhvst/barbell
    owner = "jhvst";
    repo = name;
    rev = "6583e6bc553611cbe42ac696eea734cfb9cb75e2";
    sha256 = "sha256-+Zu3KgMjq+qL1SGQZNX4fV31DTeJETK8EroND5BHS+U=";
  };
  barbell-script = pkgs.writeScriptBin name ''
    #!/usr/bin/env bash
    ${pkgs.cbqn}/bin/cbqn ${src}/barbell.bqn "$@"
  '';
in
pkgs.stdenv.mkDerivation {
  name = name;
  buildInputs = [ pkgs.cbqn ];
  shellHook = ''
    export PATH="$PATH:${barbell-script}/bin"
  '';
}
