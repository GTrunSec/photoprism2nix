final: prev:
let
  flakeLock = prev.lib.importJSON ./flake.lock;
  loadInput = { locked, ... }:
    assert locked.type == "github";
    builtins.fetchTarball {
      url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
      sha256 = locked.narHash;
    };

  ranz2nix = loadInput flakeLock.nodes.ranz2nix;
in
rec {
  ranz2nix = prev.callPackage "${ranz2nix}" { };
}
