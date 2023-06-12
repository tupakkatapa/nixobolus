{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # This one contains whatever you want to overlay
  modifications = final: prev: {
    lighthouse = prev.lighthouse.overrideAttrs (oldAttrs: rec {
      # Version override
      pname = "lighthouse";
      version = "4.0.2-rc.0";
      src = final.fetchFromGitHub {
        owner = "sigp";
        repo = "lighthouse";
        rev = "v${version}";
        hash = "sha256-10DpoG9MS6jIod0towzIsmyyakfiT62NIJBKxqsgsK0=";
      };
      # Enables aggressive optimisations including full LTO
      PROFILE = "maxperf";
    });
    erigon = prev.lighthouse.overrideAttrs (oldAttrs: rec {
      # Version override
      pname = "erigon";
      version = "2.42.0";
      src = final.fetchFromGitHub {
        owner = "ledgerwatch";
        repo = pname;
        rev = "v${version}";
        sha256 = "sha256-M2u8/WKo1yZu27KjTJhJFqycCxCopJqtVQpIs9inswI=";
        fetchSubmodules = true;
      };
      vendorSha256 = "sha256-Vyurf4wSN4zSDjcH8FC+OOiviiSjRVF4RId/eqFDd+c=";
    });
  };
}