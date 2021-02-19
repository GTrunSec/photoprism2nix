{
  inputs = {
    nixpkgs.url = "nixpkgs/7ff5e241a2b96fff7912b7d793a06b4374bd846c";
    ranz2nix = { url = "github:andir/ranz2nix"; flake = false; };
    photoprism = { url = "github:photoprism/photoprism/cc05c430535013fd10ca340220d8c1794d572d57"; flake = false; };
  };

  outputs = inputs@{ self, nixpkgs, ranz2nix, photoprism }: {

    overlay = final: prev: {
      photoprism = self.defaultPackage.x86_64-linux;
    };

    nixosModules.photoprism = { lib, pkgs, config, ... }: {
      options = with lib; {
        services.photoprism = {
          enable = mkOption {
            type = types.bool;
            default = false;
          };
          port = mkOption {
            type = types.str;
            default = "2342";
          };
          http_host = mkOption {
            type = types.str;
            default = "127.0.0.1";
          };
        };
      };

      config = with lib; {
        users.users.photoprism = { isSystemUser = true; group = "photoprism"; };

        users.groups.photoprism = { };

        systemd.services.photoprism = {
          enable = true;
          after = [
            "network-online.target"
            #"mysql.service"
          ];
          wantedBy = [ "multi-user.target" ];

          confinement = {
            enable = true;
            binSh = null;
            packages = [
              pkgs.libtensorflow-bin
              pkgs.darktable
              pkgs.ffmpeg
              pkgs.exiftool
              self.outputs.defaultPackage.x86_64-linux
              pkgs.cacert
            ];
          };

          path = [
            pkgs.libtensorflow-bin
            pkgs.darktable
            pkgs.ffmpeg
            pkgs.exiftool
          ];
          script = ''
            exec ${self.outputs.defaultPackage.x86_64-linux}/bin/photoprism --assets-path ${self.outputs.defaultPackage.x86_64-linux.assets} start
          '';

          serviceConfig = {
            User = "photoprism";
            RuntimeDirectory = "photoprism";
            CacheDirectory = "photoprism";
            StateDirectory = "photoprism";
            SyslogIdentifier = "photoprism";
            PrivateTmp = true;
          };


          environment = (
            lib.mapAttrs' (n: v: lib.nameValuePair "PHOTOPRISM_${n}" (toString v)) {
              #HOME = "/var/lib/photoprism";
              SSL_CERT_DIR = "${pkgs.cacert}/etc/ssl/certs";

              ADMIN_PASSWORD = "photoprism";
              DARKTABLE_PRESETS = "false";
              #DATABASE_DRIVER = "mysql";
              DATABASE_DRIVER = "sqlite";

              DATABASE_DSN = "/var/lib/photoprism/photoprism.sqlite";
              #DATABASE_DSN = "photoprism@unix(/run/mysqld/mysqld.sock)/photoprism?charset=utf8mb4,utf8&parseTime=true";
              DEBUG = "true";
              DETECT_NSFW = "true";
              EXPERIMENTAL = "true";
              WORKERS = "8";
              ORIGINALS_LIMIT = "1000000";
              HTTP_HOST = "${config.services.photoprism.http_host}";
              HTTP_PORT = "${config.services.photoprism.port}";
              HTTP_MODE = "release";
              JPEG_QUALITY = "92";
              JPEG_SIZE = "7680";
              PUBLIC = "false";
              READONLY = "false";
              TENSORFLOW_OFF = "true";
              SIDECAR_JSON = "true";
              SIDECAR_YAML = "true";
              SIDECAR_PATH = "/var/lib/photoprism/sidecar";
              SETTINGS_HIDDEN = "false";
              SITE_CAPTION = "Browse Your Life";
              SITE_TITLE = "PhotoPrism";
              SITE_URL = "http://127.0.0.1:2342/";
              STORAGE_PATH = "/var/lib/photoprism/storage";
              ASSETS_PATH = "${self.outputs.defaultPackage.x86_64-linux.assets}";
              ORIGINALS_PATH = "/var/lib/photoprism/originals";
              IMPORT_PATH = "/var/lib/photoprism/import";
              THUMB_FILTER = "linear";
              THUMB_SIZE = "2048";
              THUMB_SIZE_UNCACHED = "7680";
              THUMB_UNCACHED = "true";
              UPLOAD_NSFW = "true";
            }
          );
        };
      };
    };

    defaultPackage.x86_64-linux =
      with import nixpkgs { system = "x86_64-linux"; overlays = [ (import ./overlay.nix) ]; };
      let
        src = pkgs.fetchFromGitHub {
          owner = "photoprism";
          repo = "photoprism";
          rev = photoprism.rev;
          sha256 = photoprism.narHash;
        };
      in
      buildGoModule {
        name = "photoprism";
        inherit src;

        subPackages = [ "cmd/photoprism" ];

        buildInputs = [ libtensorflow-bin ];

        prePatch = ''
          substituteInPlace internal/commands/passwd.go --replace '/bin/stty' "${coreutils}/bin/stty"
          sed -i 's/zip.Deflate/zip.Store/g' internal/api/zip.go
        '';

        vendorSha256 = "sha256-j1jD3nCTMy/38A/DzdWIfRrvvVsmi3aHGUGrH4Zjsdc=";

        passthru = rec {

          frontend =
            let
              noderanz = callPackage ranz2nix {
                nodejs = nodejs-12_x;
                sourcePath = src + "/frontend";
                packageOverride = name: spec:
                  if name == "minimist" && spec ? resolved && spec.resolved == "" && spec.version == "1.2.0" then {
                    resolved = "file://" + (
                      toString (
                        fetchurl {
                          url = "https://registry.npmjs.org/minimist/-/minimist-1.2.0.tgz";
                          sha256 = "0w7jll4vlqphxgk9qjbdjh3ni18lkrlfaqgsm7p14xl3f7ghn3gc";
                        }
                      )
                    );
                  } else { };
              };
              node_modules = noderanz.patchedBuild;
            in
            stdenv.mkDerivation {
              name = "photoprism-frontend";
              nativeBuildInputs = [ nodejs-12_x ];

              inherit src;

              sourceRoot = "source/frontend";

              postUnpack = ''
                chmod -R +rw .
              '';

              NODE_ENV = "production";

              buildPhase = ''
                export HOME=$(mktemp -d)
                ln -sf ${node_modules}/node_modules node_modules
                ln -sf ${node_modules.lockFile} package-lock.json
                npm run build
              '';
              installPhase = ''
                cp -rv ../assets/static/build $out
              '';
            };

          assets =
            let
              nasnet = fetchzip {
                url = "https://dl.photoprism.org/tensorflow/nasnet.zip";
                sha256 = "09cnr2wpc09xrv1crms3mfcl61rxf4nr5j51ppy4ng6bxg9rq5s1";
              };

              nsfw = fetchzip {
                url = "https://dl.photoprism.org/tensorflow/nsfw.zip";
                sha256 = "0j0r39cgrr0zf2sc1hpr8jh19lr3jxdw9wz6sq3s7kkqay324ab8";
              };

            in
            runCommand "photoprims-assets" { } ''
              cp -rv ${src}/assets $out
              chmod -R +rw $out
              rm -rf $out/static/build
              cp -rv ${frontend} $out/static/build
              ln -s ${nsfw} $out/nsfw
              ln -s ${nasnet} $out/nasnet
            '';
        };
      };
    checks.x86_64-linux.build = self.defaultPackage.x86_64-linux;
  };
}
