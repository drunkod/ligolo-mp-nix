{
  description = "A Ligolo-ng flake for running the proxy and agent with a pre-configured tunnel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ligoloPackage = pkgs.ligolo-ng;

      in
      {
        # Packages define runnable wrapper scripts.
        packages = {
          # Package to run the Ligolo-ng proxy (server-side).
          ligolo-proxy = pkgs.writeShellScriptBin "run-ligolo-proxy" ''
            #!${pkgs.stdenv.shell}
            echo "### Starting Ligolo-ng Proxy with Config File ###"

            if [ "$(id -u)" -ne 0 ]; then
                echo "ERROR: This command must be run with root privileges (e.g., using 'sudo')."
                exit 1
            fi

            echo "The process will run in the background."

            # Use '-daemon' to run as a background process.
            # Use '-selfcert' for easy testing without real certs.
            # Use '-config' to load our pre-configured interface and routes.
            exec ${ligoloPackage}/bin/proxy -daemon -selfcert -config ligolo-ng.yaml "$@"
          '';

          # Package to run the Ligolo-ng agent (client-side).
          ligolo-agent = pkgs.writeShellScriptBin "run-ligolo-agent" ''
            #!${pkgs.stdenv.shell}
            echo "### Starting Ligolo-ng Agent ###"
            if [ $# -eq 0 ]; then
                echo "ERROR: Please provide connection arguments." >&2
                echo "Usage: nix run .#agent -- -connect YOUR_VPS_IP:11601 -ignore-cert"
                exit 1
            fi
            echo "Connecting to proxy with arguments: $@"
            # The agent does not require root privileges, but you must run it with
            # 'sudo' if you want it to create a TUN interface on the client.
            exec ${ligoloPackage}/bin/agent "$@"
          '';

          # Expose the raw ligolo-ng package.
          ligolo-ng = ligoloPackage;
        };

        # Apps allow running packages directly with 'nix run'.
        apps = {
          proxy = {
            type = "app";
            program = "${self.packages.${system}.ligolo-proxy}/bin/run-ligolo-proxy";
          };
          agent = {
            type = "app";
            program = "${self.packages.${system}.ligolo-agent}/bin/run-ligolo-agent";
          };
        };

        defaultApp = self.apps.${system}.proxy;

        devShells.default = pkgs.mkShell {
          name = "ligolo-ng-dev-shell";
          buildInputs = [ ligoloPackage pkgs.iproute2 ];
          shellHook = ''
            echo "### Ligolo-ng Development Shell ###"
            echo "The 'proxy' and 'agent' executables are in your PATH."
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      }
    );
}
