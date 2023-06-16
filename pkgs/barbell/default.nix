{ pkgs ? import <nixpkgs> { } 
, lib ? pkgs.lib
}:

let
  name = "barbell";
  src = pkgs.fetchFromGitHub {
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
  meta = with lib; {
    homepage = "https://github.com/jhvst/barbell";
    description = "Barbell is like the templating system Handlebars, but with BQN's Under doing the heavy lifting ";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
