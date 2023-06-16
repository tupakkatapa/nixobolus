{ pkgs ? import <nixpkgs> { } }:
{
  # example = pkgs.callPackage ./example { };
  barbell = pkgs.callPackage ./barbell { };
}
