{
  description = "Photo management software";

  outputs = { self, nixpkgs }: {

    nixosModules.photoprism = { lib, pkgs, config, ... }: {
      options = with lib; {
        services.photoprism = mkOption {
          default = { };
          type = types.loaOf (types.submodule ({ name, ... }: {
            options = {
              enable = mkOption {
                type = types.bool;
                default = false;
              };
            };
          }));
        };
      };

      config = with lib; {
        users.users.photoprism = { isSystemUser = true; group = "photoprism"; };

        users.groups.photoprism = { };

        systemd.services.photoprism = {
          enable = true;
          after = [ "network-online.target" "mysql.service" ];
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

          serviceConfig = {
            Restart = "always";
            RestartSec = "10";
            User = "photoprism";
            #TemporaryFileSystem = [ "/" "/etc" ];
            #BindReadOnlyPaths = [
              #"-/etc/hosts"
              #"-/etc/resolv.conf"
            #];
            ExecStart = mkDefault "${self.outputs.defaultPackage.x86_64-linux}/bin/photoprism start";
            #WorkingDirectory = "/var/lib/photoprism";
            StateDirectory = "photoprism";
            BindPaths = [
              "/var/lib/photoprism"
              "-/run/mysqld"
              "-/var/run/mysqld"
            ];
            PrivateUsers = true;
            PrivateDevices = true;
            ProtectClock = true;
            ProtectKernelLogs = true;
            SystemCallArchitectures = "native";
            RestrictNamespaces = true;
            MemoryDenyWriteExecute = true;
            CapabilityBoundingSet = [ "" ];
            AmbientCapabilities = [ "" ];
            #IPAddressDeny = "any";
            #IPAddressAllow = "localhost";
            RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
            RestrictSUIDSGID = true;
            NoNewPrivileges = true;
            RemoveIPC = true;
            LockPersonality = true;
            ProtectHome = true;
            ProtectHostname = true;
            RestrictRealtime = true;
            SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
            SystemCallErrorNumber = "EPERM";
          };


          environment = {
            #HOME = "/var/lib/photoprism";
            SSL_CERT_DIR = "${pkgs.cacert}/etc/ssl/certs";

            PHOTOPRISM_ADMIN_PASSWORD = "photoprism";
            PHOTOPRISM_DARKTABLE_PRESETS = "false";
            PHOTOPRISM_DATABASE_DRIVER = "mysql";
            PHOTOPRISM_DATABASE_DSN = "photoprism@unix(/run/mysqld/mysqld.sock)/photoprism?charset=utf8mb4,utf8&parseTime=true";
            PHOTOPRISM_DEBUG = "true";
            PHOTOPRISM_DETECT_NSFW = "true";
            PHOTOPRISM_EXPERIMENTAL = "true";
            PHOTOPRISM_WORKERS = "8";
            PHOTOPRISM_ORIGINALS_LIMIT = "1000000";
            PHOTOPRISM_HTTP_HOST = "127.0.0.1";
            PHOTOPRISM_HTTP_PORT = "2342";
            PHOTOPRISM_HTTP_MODE = "release";
            PHOTOPRISM_JPEG_QUALITY = "92";
            PHOTOPRISM_JPEG_SIZE = "7680";
            PHOTOPRISM_PUBLIC = "false";
            PHOTOPRISM_READONLY = "false";
            PHOTOPRISM_TENSORFLOW_OFF = "true";
            PHOTOPRISM_SIDECAR_JSON = "true";
            PHOTOPRISM_SIDECAR_YAML = "true";
            PHOTOPRISM_SETTINGS_HIDDEN = "false";
            PHOTOPRISM_SITE_CAPTION = "Browse Your Life";
            PHOTOPRISM_SITE_TITLE = "PhotoPrism";
            PHOTOPRISM_SITE_URL = "http://127.0.0.1:2342/";
            PHOTOPRISM_STORAGE_PATH = "/var/lib/photoprism/storage";
            #PHOTOPRISM_ASSETS_PATH = "${self.outputs.defaultPackage.x86_64-linux}/usr/lib/photoprism/assets";
            PHOTOPRISM_ASSETS_PATH = "/var/lib/photoprism/assets";
            PHOTOPRISM_ORIGINALS_PATH = "/var/lib/photoprism/originals";
            PHOTOPRISM_IMPORT_PATH = "/var/lib/photoprism/import";
            PHOTOPRISM_THUMB_FILTER = "linear";
            PHOTOPRISM_THUMB_SIZE = "2048";
            PHOTOPRISM_THUMB_SIZE_UNCACHED = "7680";
            PHOTOPRISM_THUMB_UNCACHED = "true";
            PHOTOPRISM_UPLOAD_NSFW = "true";
          };
        };
      };
    };

    defaultPackage.x86_64-linux =
      with import nixpkgs { system = "x86_64-linux"; };
      buildGoModule {
        name = "photoprism";
        src = pkgs.fetchFromGitHub {
          owner = "photoprism";
          repo = "photoprism";
          rev = "82b6de24d3477df8c21262215d729822b3791bd7";
          sha256 = "1lbfcyjcsypjf06gs6qnf8dnf73yygpiyacwnl6qn9h11r1d3ffw";
        };

        vendorSha256 = "sha256-qgSmTv7hO1rmOxCXBaDtbdlkUtKZ16zSu4S3SVKn3Ew=";

        doCheck = false;

        subPackages = [ "cmd/photoprism" ];

	#preBuild = ''
          #patchShebangs ./
	  #sed -i 's/\/tmp\/photoprism/\$\{tmp\}/' scripts/download-nsfw.sh
	  #sed -i 's/\/tmp\/photoprism/\$\{tmp\}/' scripts/download-nasnet.sh
	  #cd frontend
	  #npm install
	  #npm audit fix
	  #make dep-go
	  #make build-js
	#'';

        postInstall = ''
          mkdir -p $out/usr/lib/photoprism/assets/{,nasnet,nsfw}
          cp -r $src/assets/static $src/assets/profiles $src/assets/templates $out/usr/lib/photoprism/assets
        '';

        nativeBuildInputs = with pkgs; [ 
	  nodejs
	  unzip
	  which
	  wget
	];

        buildInputs = with pkgs; [ 
	  libtensorflow-bin
	];
      };
  };
}
