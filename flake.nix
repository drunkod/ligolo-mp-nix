{
  description = "A Ligolo-MP flake for running the server and client with an integrated E2E test.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    ligolo-mp-src = {
      # It's best practice to pin to a specific commit hash for true reproducibility.
      # You can get this by running `nix flake lock --update-input ligolo-mp-src`
      url = "github:ttpreport/ligolo-mp/main";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ligolo-mp-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # --- Common Build Logic ---
        # By creating a base derivation, we avoid repeating common attributes.
        ligolo-mp-base = pkgs.buildGoModule {
          pname = "ligolo-mp";
          version = "2"; # This could be derived from a tag if one existed
          src = ligolo-mp-src;
          ldflags = [ "-s" "-w" ];
          vendorHash = null;
        };

        # --- Package Definitions ---
        # The unwrapped packages are now much cleaner.
        ligolo-mp-server-unwrapped = ligolo-mp-base.overrideAttrs (old: {
          pname = "${old.pname}-server";
          nativeBuildInputs = [ pkgs.gnumake pkgs.zip pkgs.curl pkgs.garble pkgs.go ];
          postPatch = ''
            make assets
          '';
          sourceRoot = "source";
          subPackages = [ "cmd/server" ];
          postInstall = ''
            mv $out/bin/server $out/bin/ligolo-mp-server
          '';
        });

        ligolo-mp-client-unwrapped = ligolo-mp-base.overrideAttrs {
          pname = "ligolo-mp-client";
          subPackages = [ "cmd/client" ];
          postInstall = ''
            mv $out/bin/client $out/bin/ligolo-mp-client
          '';
        };

        ligolo-mp-agent-for-test = ligolo-mp-base.overrideAttrs (old: {
          pname = "${old.pname}-agent";
          sourceRoot = "source/artifacts/agent";
          subPackages = [ "." ];
          postPatch = ''
            substituteInPlace agent.go \
              --replace '{{ .ProxyServer }}' "" \
              --replace '{{ .Servers }}' "server:11601" \
              --replace '{{ .AgentCert }}' "" \
              --replace '{{ .AgentKey }}' "" \
              --replace '{{ .CACert }}' "" \
              --replace '{{ .IgnoreEnvProxy }}' "true"
          '';
          postInstall = ''
            mv $out/bin/ligolo-mp-agent $out/bin/agent
          '';
        });

        # --- NixOS Module Definition ---
        # Define the module once in the `let` block for clarity.
        ligolo-mp-module = { lib, config, ... }: {
          options = {
            services.ligolo-mp-server.enable = lib.mkEnableOption "Enable the Ligolo-MP server daemon.";
            services.ligolo-mp-agent.enable = lib.mkEnableOption "Enable the Ligolo-MP test agent.";
          };

          config = lib.mkMerge [
            (lib.mkIf (config.services.ligolo-mp-server.enable || config.services.ligolo-mp-agent.enable) {
              nix.settings.extra-experimental-features = [ "nix-command" "flakes" ];
            })
            (lib.mkIf config.services.ligolo-mp-server.enable {
              networking.firewall.allowedTCPPorts = [ 11601 58008 ];
              systemd.services.ligolo-mp-server = {
                description = "Ligolo-MP Server Daemon";
                wantedBy = [ "multi-user.target" ];
                after = [ "network.target" ];
                serviceConfig = {
                  ExecStart = "${ligolo-mp-server-unwrapped}/bin/ligolo-mp-server -daemon -agent-addr 0.0.0.0:11601 -operator-addr 0.0.0.0:58008";
                  Restart = "on-failure";
                  RestartSec = 3;
                  User = "root";
                };
              };
            })
            (lib.mkIf config.services.ligolo-mp-agent.enable {
                systemd.services.ligolo-mp-agent = {
                  description = "Ligolo-MP Test Agent";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" ];
                  path = [ pkgs.sudo ];
                  serviceConfig = {
                    ExecStart = "${ligolo-mp-agent-for-test}/bin/agent -connect server:11601 -ignore-cert";
                    Restart = "on-failure";
                    RestartSec = 3;
                    User = "root";
                  };
                };
            })
          ];
        };

      in
      {
        # --- Exposed Packages and Apps ---
        packages = {
          server = ligolo-mp-server-unwrapped;
          client = ligolo-mp-client-unwrapped;
          default = self.packages.${system}.client;
        };

        apps = {
          server = { type = "app"; program = "${self.packages.${system}.server}/bin/ligolo-mp-server"; };
          client = { type = "app"; program = "${self.packages.${system}.client}/bin/ligolo-mp-client"; };
          default = self.apps.${system}.client;
        };

        # --- NixOS Module ---
        nixosModules.default = ligolo-mp-module;

        # --- Development Environment ---
        devShells.default = pkgs.mkShell {
          name = "ligolo-mp-dev-shell";
          packages = [
            self.packages.${system}.server
            self.packages.${system}.client
            pkgs.iproute2
          ];
        };

        # --- Automated Checks ---
        checks.e2e-test = pkgs.nixosTest {
          name = "ligolo-mp-e2e-test";
          nodes = {
            # References to the module are now cleaner.
            server = { ... }: { imports = [ ligolo-mp-module ]; services.ligolo-mp-server.enable = true; };
            client = { ... }: { imports = [ ligolo-mp-module ]; services.ligolo-mp-agent.enable = true; };
          };

          testScript = ''
            start_all()

            server.wait_for_unit("ligolo-mp-server.service")
            server.wait_for_open_port(11601)
            client.wait_for_unit("ligolo-mp-agent.service")

            # Give the agent time to connect
            server.sleep(5)

            # Confirm the server logged a new session from the client.
            with server.nested("Testing for new session"):
                server.succeed("journalctl -u ligolo-mp-server --no-pager | grep 'new session with'")
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
