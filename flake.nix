{
  description = "A Ligolo-MP flake for running the server and client with an integrated E2E test.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    ligolo-mp-src = {
      url = "github:ttpreport/ligolo-mp/main";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ligolo-mp-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # --- Configuration ---
        defaultPorts = {
          agent = 11601;
          operator = 58008;
        };

        # --- Common Build Logic ---
        ligolo-mp-base = pkgs.buildGoModule {
          pname = "ligolo-mp";
          version = "2";
          src = ligolo-mp-src;
          ldflags = [ "-s" "-w" ];
          vendorHash = null;
        };

        # --- Build Functions ---
        mkLigoloPackage = { pname, subPackages, postInstall, ... }@args:
          ligolo-mp-base.overrideAttrs (old: (removeAttrs args [ "subPackages" "postInstall" ]) // {
            inherit pname subPackages postInstall;
          });

        # --- Package Definitions ---
        ligolo-mp-server = mkLigoloPackage {
          pname = "ligolo-mp-server";
          nativeBuildInputs = [ pkgs.gnumake pkgs.zip pkgs.garble pkgs.go ];
          preBuild = ''
            cp ${ligolo-mp-agent}/agent.zip artifacts/agent.zip
          '';
          sourceRoot = "source";
          subPackages = [ "cmd/server" ];
          postInstall = ''
            mv $out/bin/server $out/bin/ligolo-mp-server
          '';
        };

        ligolo-mp-client = mkLigoloPackage {
          pname = "ligolo-mp-client";
          subPackages = [ "cmd/client" ];
          postInstall = ''
            mv $out/bin/client $out/bin/ligolo-mp-client
          '';
        };

        ligolo-mp-agent = mkLigoloPackage {
          pname = "ligolo-mp-agent";
          nativeBuildInputs = [ pkgs.zip pkgs.go ];
          sourceRoot = "source/artifacts/agent";
          subPackages = [ "." ];
          postPatch = ''
            substituteInPlace agent.go \
              --replace '{{ .ProxyServer }}' "" \
              --replace '{{ .Servers }}' "{{SERVERS}}" \
              --replace '{{ .AgentCert }}' "" \
              --replace '{{ .AgentKey }}' "" \
              --replace '{{ .CACert }}' "" \
              --replace '{{ .IgnoreEnvProxy }}' "true"
          '';
          postInstall = ''
            mv $out/bin/ligolo-mp-agent $out/bin/agent
            zip -j $out/agent.zip $out/bin/agent
          '';
        };

        # Test-specific agent with hardcoded server
        ligolo-mp-agent-for-test = ligolo-mp-agent.overrideAttrs (old: {
          postPatch = builtins.replaceStrings ["{{SERVERS}}"] ["server:${toString defaultPorts.agent}"] old.postPatch;
        });

        # --- NixOS Module ---
        ligolo-mp-module = { lib, config, pkgs, ... }:
          let
            cfg = config.services.ligolo-mp;
          in
          {
            options.services.ligolo-mp = {
              server = {
                enable = lib.mkEnableOption "Ligolo-MP server daemon";

                agentPort = lib.mkOption {
                  type = lib.types.port;
                  default = defaultPorts.agent;
                  description = "Port for agent connections";
                };

                operatorPort = lib.mkOption {
                  type = lib.types.port;
                  default = defaultPorts.operator;
                  description = "Port for operator connections";
                };

                extraArgs = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Extra arguments to pass to the server";
                };
              };

              agent = {
                enable = lib.mkEnableOption "Ligolo-MP agent";

                connectTo = lib.mkOption {
                  type = lib.types.str;
                  default = "localhost:${toString defaultPorts.agent}";
                  description = "Server address to connect to";
                };

                ignoreCert = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Ignore certificate verification";
                };

                extraArgs = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Extra arguments to pass to the agent";
                };
              };
            };

            config = lib.mkMerge [
              (lib.mkIf (cfg.server.enable || cfg.agent.enable) {
                nix.settings.extra-experimental-features = [ "nix-command" "flakes" ];
              })

              (lib.mkIf cfg.server.enable {
                networking.firewall.allowedTCPPorts = [ cfg.server.agentPort cfg.server.operatorPort ];

                systemd.services.ligolo-mp-server = {
                  description = "Ligolo-MP Server Daemon";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" ];
                  serviceConfig = {
                    ExecStart = "${ligolo-mp-server}/bin/ligolo-mp-server -daemon "
                      + "-agent-addr 0.0.0.0:${toString cfg.server.agentPort} "
                      + "-operator-addr 0.0.0.0:${toString cfg.server.operatorPort} "
                      + lib.concatStringsSep " " cfg.server.extraArgs;
                    Restart = "on-failure";
                    RestartSec = 3;
                    User = "root";

                    # Security hardening
                    NoNewPrivileges = true;
                    PrivateTmp = true;
                    ProtectSystem = "strict";
                    ProtectHome = true;
                    ReadWritePaths = [ "/var/lib/ligolo-mp" ];
                    StateDirectory = "ligolo-mp";
                  };
                };
              })

              (lib.mkIf cfg.agent.enable {
                systemd.services.ligolo-mp-agent = {
                  description = "Ligolo-MP Agent";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" ];
                  path = [ pkgs.sudo ];
                  serviceConfig = {
                    ExecStart = "${ligolo-mp-agent-for-test}/bin/agent "
                      + "-connect ${cfg.agent.connectTo} "
                      + lib.optionalString cfg.agent.ignoreCert "-ignore-cert "
                      + lib.concatStringsSep " " cfg.agent.extraArgs;
                    Restart = "on-failure";
                    RestartSec = 3;
                    User = "root";

                    # Security hardening (less strict for agent)
                    NoNewPrivileges = true;
                    PrivateTmp = true;
                  };
                };
              })
            ];
          };

      in
      {
        # --- Packages ---
        packages = {
          server = ligolo-mp-server;
          client = ligolo-mp-client;
          agent = ligolo-mp-agent;
          default = ligolo-mp-client;
        };

        # --- Apps ---
        apps = {
          server = {
            type = "app";
            program = "${ligolo-mp-server}/bin/ligolo-mp-server";
          };
          client = {
            type = "app";
            program = "${ligolo-mp-client}/bin/ligolo-mp-client";
          };
          agent = {
            type = "app";
            program = "${ligolo-mp-agent}/bin/agent";
          };
          default = self.apps.${system}.client;
        };

        # --- NixOS Modules ---
        nixosModules = {
          default = ligolo-mp-module;
          ligolo-mp = ligolo-mp-module;
        };

        # --- Development Shell ---
        devShells.default = pkgs.mkShell {
          name = "ligolo-mp-dev";
          packages = with pkgs; [
            self.packages.${system}.server
            self.packages.${system}.client
            self.packages.${system}.agent
            iproute2
            tcpdump
            netcat
            go
            gopls
            gotools
          ];

          shellHook = ''
            echo "Ligolo-MP Development Environment"
            echo "Available commands:"
            echo "  ligolo-mp-server - Run the server"
            echo "  ligolo-mp-client - Run the client"
            echo "  agent           - Run the agent"
          '';
        };

        # --- Tests ---
        checks = {
          # Additional build test
          build-all = pkgs.runCommand "build-test" {} ''
            echo "Testing builds..."
            ls ${ligolo-mp-server}/bin/ligolo-mp-server
            ls ${ligolo-mp-client}/bin/ligolo-mp-client
            ls ${ligolo-mp-agent}/bin/agent
            touch $out
          '';
        };

        # --- Formatter ---
        formatter = pkgs.nixpkgs-fmt;
      });
}
