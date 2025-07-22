{
  description = "A comprehensive Ligolo-MP flake using v2.0.1 pre-compiled binaries.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # --- Configuration ---
        version = "2.0.1";

        systemToArch = {
          "x86_64-linux" = "amd64";
          "aarch64-linux" = "arm64";
        };

        hashes = {
          linux = {
            amd64 = {
              main = "5b8936131264e4fe298cdbef9818a5acbfbedc76b3f4b3316d6291584b2761a2";
              client = "b2bb3d4d8717c378b7387c3706f3aadb258d1b37fb490b21e111408610e8629d";
            };
            arm64 = {
              main = "ee69543eb5b77e0deaefc47015ebec933d0ec81bb8334ce82e84034891ac44fd";
              client = "35a4a9162dbed4daed7c33268090852e2c04d519493c4ad21967ec68cdf63a04";
            };
          };
        };

        arch = systemToArch.${system} or (throw "Unsupported system: ${system}");
        os = "linux";

        # --- Package Builders ---
        mkLigoloBinaryPackage = { drvName, assetName, sha256, executableName, ... }:
          pkgs.stdenv.mkDerivation {
            pname = drvName;
            inherit version;
            src = pkgs.fetchurl {
              url = "https://github.com/ttpreport/ligolo-mp/releases/download/v${version}/${assetName}_${os}_${arch}";
              inherit sha256;
            };
            dontUnpack = true;
            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/${executableName}
              chmod +x $out/bin/${executableName}
            '';
          };

        ligolo-mp = mkLigoloBinaryPackage {
          drvName = "ligolo-mp";
          assetName = "ligolo-mp";
          executableName = "ligolo-mp";
          sha256 = hashes.${os}.${arch}.main;
        };

        ligolo-mp-client = mkLigoloBinaryPackage {
          drvName = "ligolo-mp-client";
          assetName = "ligolo-mp_client";
          executableName = "ligolo-mp-client";
          sha256 = hashes.${os}.${arch}.client;
        };

        ligolo-mp-server = pkgs.runCommand "ligolo-mp-server-link" { } ''
          mkdir -p $out/bin
          ln -s ${ligolo-mp}/bin/ligolo-mp $out/bin/ligolo-mp-server
        '';

        ligolo-mp-agent = pkgs.runCommand "ligolo-mp-agent-link" { } ''
          mkdir -p $out/bin
          ln -s ${ligolo-mp}/bin/ligolo-mp $out/bin/agent
        '';

        # --- NixOS Module ---
        ligolo-mp-module = { lib, config, ... }:
          let
            cfg = config.services.ligolo-mp;
            stateDir = "/var/lib/ligolo-mp";
            defaultPorts = { agent = 11601; operator = 58008; };
          in
          {
            options.services.ligolo-mp = {
              server = {
                enable = lib.mkEnableOption "Ligolo-MP server daemon";
                agentPort = lib.mkOption { type = lib.types.port; default = defaultPorts.agent; };
                operatorPort = lib.mkOption { type = lib.types.port; default = defaultPorts.operator; };
              };
              agent = {
                enable = lib.mkEnableOption "Ligolo-MP agent";
                connectTo = lib.mkOption { type = lib.types.str; };
                ignoreCert = lib.mkOption { type = lib.types.bool; default = false; };
              };
            };
            config = lib.mkMerge [
              (lib.mkIf cfg.server.enable {
                networking.firewall.allowedTCPPorts = [ cfg.server.agentPort cfg.server.operatorPort ];
                systemd.services.ligolo-mp-server = {
                  description = "Ligolo-MP Server Daemon";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" ];
                  serviceConfig = {
                    ExecStart = ''
                      ${ligolo-mp-server}/bin/ligolo-mp-server -daemon \
                        --config-path ${stateDir} -agent-addr "0.0.0.0:${toString cfg.server.agentPort}" -operator-addr "0.0.0.0:${toString cfg.server.operatorPort}"
                    '';
                    Restart = "on-failure";
                    User = "root";
                    NoNewPrivileges = true;
                    PrivateTmp = true;
                    ProtectSystem = "strict";
                    ProtectHome = true;
                    ReadWritePaths = [ stateDir ];
                    StateDirectory = "ligolo-mp";
                  };
                };
              })
              (lib.mkIf cfg.agent.enable {
                systemd.services.ligolo-mp-agent = {
                  description = "Ligolo-MP Agent";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" ];
                  serviceConfig = {
                    ExecStart = ''
                      ${ligolo-mp-agent}/bin/agent -connect "${cfg.agent.connectTo}" ${lib.optionalString cfg.agent.ignoreCert "-ignore-cert"}
                    '';
                    Restart = "on-failure";
                    User = "root";
                    NoNewPrivileges = true;
                    PrivateTmp = true;
                  };
                };
              })
            ];
          };

      in
      {
        # --- Flake Outputs ---
        packages = {
          inherit ligolo-mp ligolo-mp-client ligolo-mp-server ligolo-mp-agent;
          default = ligolo-mp-client;
        };

        apps = {
          server = { type = "app"; program = "${ligolo-mp-server}/bin/ligolo-mp-server"; };
          client = { type = "app"; program = "${ligolo-mp-client}/bin/ligolo-mp-client"; };
          agent  = { type = "app"; program = "${ligolo-mp-agent}/bin/agent"; };
          default = self.apps.${system}.client;
        };

        nixosModules.default = ligolo-mp-module;

        devShells.default = pkgs.mkShell {
          name = "ligolo-mp-shell";
          packages = [ ligolo-mp ligolo-mp-client pkgs.netcat ];
        };
        
        checks.e2e-test = pkgs.nixosTest {
          name = "ligolo-mp-e2e-test-binary";
          nodes = {
            server = { imports = [ ligolo-mp-module ]; services.ligolo-mp.server.enable = true; };
            agent = { imports = [ ligolo-mp-module ]; services.ligolo-mp.agent = { enable = true; connectTo = "server:11601"; ignoreCert = true; }; };
          };
          testScript = ''
            start_all()
            server.wait_for_unit("ligolo-mp-server.service")
            server.wait_for_open_port(11601)
            server.wait_for_open_port(58008)
            agent.wait_for_unit("ligolo-mp-agent.service")
            agent.sleep(5)
            with subtest("Agent connection established"):
              server.succeed("journalctl -u ligolo-mp-server --no-pager | grep 'new session'")
            with subtest("Services remain stable"):
              server.succeed("systemctl is-active ligolo-mp-server.service")
              agent.succeed("systemctl is-active ligolo-mp-agent.service")
          '';
        };
      });
}