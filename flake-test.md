Here are several ways to check and test this flake:

## 1. Basic Flake Validation

```bash
# Check the flake's syntax and run all defined checks
nix flake check

# Show the flake's structure
nix flake show

# Check metadata
nix flake metadata
```

## 2. Build and Test Packages

```bash
# Build individual packages
nix build .#server
nix build .#client
nix build .#agent

# Build all packages at once
nix build .#server .#client .#agent

# Check the built binaries
./result/bin/ligolo-mp-server --help
./result/bin/ligolo-mp-client --help
./result/bin/agent --help
```

## 3. Run the E2E Test

```bash
# Run the end-to-end NixOS test
nix build .#checks.x86_64-linux.e2e-test

# Run with more verbose output
nix build .#checks.x86_64-linux.e2e-test --print-build-logs

# Run interactively (useful for debugging)
nix build .#checks.x86_64-linux.e2e-test.driverInteractive
./result/bin/nixos-test-driver
```

## 4. Test the Apps

```bash
# Run the server directly
nix run .#server -- --help

# Run the client
nix run .#client -- --help

# Run the agent
nix run .#agent -- --help
```

## 5. Test the Development Shell

```bash
# Enter the development shell
nix develop

# Or run a command in the shell
nix develop -c ligolo-mp-server --version
```

## 6. Test the NixOS Module

Create a test configuration file `test-config.nix`:

```nix
{ nixpkgs, ... }:
{
  nixos-test = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ./flake.nix#nixosModules.default
      {
        services.ligolo-mp.server = {
          enable = true;
          agentPort = 11601;
          operatorPort = 58008;
        };
      }
    ];
  };
}
```

## 7. Format Check

```bash
# Check if code is properly formatted
nix fmt -- --check

# Format the code
nix fmt
```

## 8. Quick Smoke Test Script

Create a `test.sh` script:

```bash
#!/usr/bin/env bash
set -e

echo "=== Checking flake structure ==="
nix flake show

echo -e "\n=== Building packages ==="
nix build .#server .#client .#agent

echo -e "\n=== Running checks ==="
nix flake check

echo -e "\n=== Testing development shell ==="
nix develop -c echo "Dev shell works!"

echo -e "\n=== All tests passed! ==="
```

## 9. Test in a VM

```bash
# Build a VM with the server enabled
nix build --impure --expr '
  (import <nixpkgs/nixos> {
    configuration = { pkgs, ... }: {
      imports = [ ./flake.nix#nixosModules.default ];
      services.ligolo-mp.server.enable = true;
      
      # Minimal VM config
      virtualisation.vmVariant = {
        virtualisation.cores = 2;
        virtualisation.memorySize = 2048;
      };
    };
  }).vm
'

# Run the VM
./result/bin/run-nixos-vm
```

## 10. Debug Failed Builds

```bash
# Get more details on failures
nix build .#server --print-build-logs -L

# Keep failed build directory for inspection
nix build .#server --keep-failed

# Show derivation details
nix show-derivation .#server
```

## Common Issues to Check:

1. **Network Access**: The build might fail if it needs network access during build time
2. **Platform Compatibility**: Some tests (like NixOS tests) only work on Linux
3. **Missing Dependencies**: Check if all required build tools are available
4. **Permissions**: Some tests might need special permissions

## Minimal Quick Check:

```bash
# This runs all essential checks
nix flake check && nix build .#server .#client .#agent
```

If all these checks pass, your flake is working correctly!
