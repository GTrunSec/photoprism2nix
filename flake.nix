{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-22.05";
    npmlock2nix = {
      url = "github:nix-community/npmlock2nix";
      flake = false;
    };
    photoprism = {
      url = "github:photoprism/photoprism";
      flake = false;
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    flake-utils.url = "github:numtide/flake-utils";
    gomod2nix = {
      url = "github:tweag/gomod2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    photoprism,
    flake-utils,
    gomod2nix,
    ...
  }:
    flake-utils.lib.eachSystem ["x86_64-linux" "x86_64-darwin" "i686-linux"]
    (
      system: let
        pkgs =
          import nixpkgs
          {
            inherit system;
            overlays = [
              self.overlays.default
              gomod2nix.overlays.default
            ];
            config = {
              allowUnsupportedSystem = true;
            };
          };
      in
        with pkgs; rec {
          packages = flake-utils.lib.flattenTree {
            inherit (pkgs)
              photoprism
              gomod2nix;
            default = pkgs.photoprism;
          };

          checks.build = packages.photoprism;

          devShells.default = mkShell {
            shellHook = ''
              # ${pkgs.photoprism}/bin/photoprism --admin-password photoprism --import-path ~/Pictures \
              #  --assets-path ${pkgs.photoprism.assets} start
            '';
          };
        }
    )
    // {
      nixosModules.photoprism = {
        lib,
        pkgs,
        config,
        ...
      }: let
        cfg = config.services.photoprism;
      in {
        options = with lib; {
          services.photoprism = {
            enable = mkOption {
              type = types.bool;
              default = false;
            };

            mysql = mkOption {
              type = types.bool;
              default = false;
            };

            port = mkOption {
              type = types.int;
              default = 2342;
            };

            host = mkOption {
              type = types.str;
              default = "127.0.0.1";
            };

            keyFile = mkOption {
              type = types.bool;
              default = false;
              description = ''
                for sops path
                 sops.secrets.photoprism-password = {
                   owner = "photoprism";
                   sopsFile = ../../secrets/secrets.yaml;
                   path = "/var/lib/photoprism/keyFile";
                 };
                 #PHOTOPRISM_ADMIN_PASSWORD=<yourpassword>
              '';
            };

            dataDir = mkOption {
              type = types.path;
              default = "/var/lib/photoprism";
              description = ''
                Data directory for photoprism
              '';
            };

            package = mkOption {
              type = types.package;
              default = self.outputs.packages."${pkgs.system}".photoprism;
              description = "The photoprism package.";
            };
          };
        };

        config = with lib;
          mkIf cfg.enable {
            users.users.photoprism = {
              isSystemUser = true;
              group = "photoprism";
            };

            users.groups.photoprism = {};

            services.mysql = mkIf cfg.mysql {
              enable = true;
              package = mkDefault pkgs.mysql;
              ensureDatabases = ["photoprism"];
              ensureUsers = [
                {
                  name = "photoprism";
                  ensurePermissions = {"photoprism.*" = "ALL PRIVILEGES";};
                }
              ];
            };

            systemd.services.photoprism = {
              enable = true;
              after =
                [
                  "network-online.target"
                ]
                ++ lib.optional cfg.mysql "mysql.service";

              wantedBy = ["multi-user.target"];

              confinement = {
                enable = true;
                binSh = null;
                packages = [
                  cfg.package.libtensorflow-bin
                  pkgs.darktable
                  pkgs.ffmpeg
                  pkgs.exiftool
                  cfg.package
                  pkgs.cacert
                ];
              };

              path = [
                cfg.package.libtensorflow-bin
                pkgs.darktable
                pkgs.ffmpeg
                pkgs.exiftool
              ];

              script = ''
                exec ${cfg.package}/bin/photoprism --assets-path ${cfg.package.assets} start
              '';

              serviceConfig = {
                User = "photoprism";
                BindPaths =
                  [
                    "/var/lib/photoprism"
                  ]
                  ++ lib.optionals cfg.mysql [
                    "-/run/mysqld"
                    "-/var/run/mysqld"
                  ];
                RuntimeDirectory = "photoprism";
                CacheDirectory = "photoprism";
                StateDirectory = "photoprism";
                SyslogIdentifier = "photoprism";
                # Sops secrets PHOTOPRISM_ADMIN_PASSWORD= /****/
                PrivateTmp = true;
                PrivateUsers = true;
                PrivateDevices = true;
                ProtectClock = true;
                ProtectKernelLogs = true;
                SystemCallArchitectures = "native";
                RestrictNamespaces = true;
                MemoryDenyWriteExecute = false;
                RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
                RestrictSUIDSGID = true;
                NoNewPrivileges = true;
                RemoveIPC = true;
                LockPersonality = true;
                ProtectHome = true;
                ProtectHostname = true;
                RestrictRealtime = true;
                SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
                SystemCallErrorNumber = "EPERM";
                EnvironmentFile = mkIf cfg.keyFile "${cfg.dataDir}/keyFile";
              };

              environment = (
                lib.mapAttrs' (n: v: lib.nameValuePair "PHOTOPRISM_${n}" (toString v))
                {
                  #HOME = "${cfg.dataDir}";
                  SSL_CERT_DIR = "${pkgs.cacert}/etc/ssl/certs";

                  DARKTABLE_PRESETS = "false";

                  DATABASE_DRIVER =
                    if !cfg.mysql
                    then "sqlite"
                    else "mysql";
                  DATABASE_DSN =
                    if !cfg.mysql
                    then "${cfg.dataDir}/photoprism.sqlite"
                    else "photoprism@unix(/run/mysqld/mysqld.sock)/photoprism?charset=utf8mb4,utf8&parseTime=true";
                  DEBUG = "true";
                  DETECT_NSFW = "true";
                  EXPERIMENTAL = "true";
                  WORKERS = "8";
                  ORIGINALS_LIMIT = "1000000";
                  HTTP_HOST = "${cfg.host}";
                  HTTP_PORT = "${toString cfg.port}";
                  HTTP_MODE = "release";
                  JPEG_QUALITY = "92";
                  JPEG_SIZE = "7680";
                  PUBLIC = "false";
                  READONLY = "false";
                  TENSORFLOW_OFF = "true";
                  SIDECAR_JSON = "true";
                  SIDECAR_YAML = "true";
                  SIDECAR_PATH = "${cfg.dataDir}/sidecar";
                  SETTINGS_HIDDEN = "false";
                  SITE_CAPTION = "Browse Your Life";
                  SITE_TITLE = "PhotoPrism";
                  SITE_URL = "http://127.0.0.1:2342/";
                  STORAGE_PATH = "${cfg.dataDir}/storage";
                  ASSETS_PATH = "${cfg.package.assets}";
                  ORIGINALS_PATH = "${cfg.dataDir}/originals";
                  IMPORT_PATH = "${cfg.dataDir}/import";
                  THUMB_FILTER = "linear";
                  THUMB_SIZE = "2048";
                  THUMB_SIZE_UNCACHED = "7680";
                  THUMB_UNCACHED = "true";
                  UPLOAD_NSFW = "true";
                }
                // (
                  if !cfg.keyFile
                  then {ADMIN_PASSWORD = "photoprism";}
                  else {}
                )
              );
            };
          };
      };

      overlays.default = final: prev: {
        photoprism = with final; (
          let
            libtensorflow-bin = prev.libtensorflow-bin.overrideAttrs (old: rec {
              # 21.05 does not have libtensorflow-bin 1.x anymore & photoprism isn't compatible with tensorflow 2.x yet
              # https://github.com/photoprism/photoprism/issues/222
              version = "1.15.0";
              src = fetchurl {
                url = "https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-cpu-linux-x86_64-${version}.tar.gz";
                sha256 = "sha256-3sv9WnCeztNSP1XM+iOTN6h+GrPgAO/aNhfbeeEDTe0=";
              };
            });
          in
            buildGoApplication {
              name = "photoprism";

              src = photoprism;

              go = prev.go_1_18;

              subPackages = ["cmd/photoprism"];

              modules = ./gomod2nix.toml;

              CGO_ENABLED = "1";
              CGO_CFLAGS = "-Wno-return-local-addr";

              buildInputs = [
                libtensorflow-bin
              ];

              prePatch = ''
                substituteInPlace internal/commands/passwd.go --replace '/bin/stty' "${coreutils}/bin/stty"
              '';

              passthru = rec {
                inherit libtensorflow-bin;

                frontend = (callPackage inputs.npmlock2nix {}).build {
                  name = "photoprism-frontend";
                  src = photoprism + "/frontend";
                  nodejs = nodejs-14_x;

                  postUnpack = ''
                    chmod -R +rw .
                  '';

                  NODE_ENV = "production";

                  buildCommands = ["npm run build"];
                  installPhase = ''
                    cp -rv ../assets/static/build $out
                  '';
                };

                assets = let
                  nasnet = fetchzip {
                    url = "https://dl.photoprism.org/tensorflow/nasnet.zip";
                    sha256 = "09cnr2wpc09xrv1crms3mfcl61rxf4nr5j51ppy4ng6bxg9rq5s1";
                  };
                  facenet = fetchzip {
                    url = "https://dl.photoprism.org/tensorflow/facenet.zip";
                    sha256 = "0vyfy7hidlzibm59236ipaymj0mzclnriv9bi86dab1sa627cqpd";
                  };
                  nsfw = fetchzip {
                    url = "https://dl.photoprism.org/tensorflow/nsfw.zip";
                    sha256 = "0j0r39cgrr0zf2sc1hpr8jh19lr3jxdw9wz6sq3s7kkqay324ab8";
                  };
                in
                  runCommand "photoprims-assets" {} ''
                    cp -rv ${photoprism}/assets $out
                    chmod -R +rw $out
                    rm -rf $out/static/build
                    cp -rv ${frontend} $out/static/build
                    ln -s ${nsfw} $out/nsfw
                    ln -s ${nasnet} $out/nasnet
                    ln -s ${facenet} $out/facenet
                  '';
              };
            }
        );
      };
    };
}
