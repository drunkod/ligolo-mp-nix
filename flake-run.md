Absolutely! Here’s a **step-by-step guide** for using your Ligolo-MP flake **imperatively** (i.e., without NixOS modules or system configuration) on **any Linux system with Nix installed**.

---

## 1. **Install Nix (if not already installed)**

If you don’t have Nix, install it:
```sh
sh <(curl -L https://nixos.org/nix/install)
```
> **Note:** You may need to log out and back in after installation.

---

## 2. **Clone the Ligolo-MP Flake**

```sh
git clone <your-flake-repo-url> ligolo-mp-flake
cd ligolo-mp-flake
```

---

## 3. **Run the Ligolo-MP Server**

On your **server** machine:

```sh
nix run .#server
```
- This will start the server with default settings (agent port 11601, operator port 58008).

**To customize ports or config:**
```sh
nix run .#server -- -daemon --config-path /tmp/ligolo-mp -agent-addr "0.0.0.0:11601" -operator-addr "0.0.0.0:58008"
```
- `-daemon` runs the server in the background.
- `--config-path` specifies where to store state/config.

---

## 4. **Run the Ligolo-MP Agent**

On your **agent** (pivot) machine:

```sh
nix run .#agent -- -connect "SERVER_IP:11601" -ignore-cert
```
- Replace `SERVER_IP` with your server’s IP or hostname.
- `-ignore-cert` disables TLS verification (for testing).

---

## 5. **Run the Ligolo-MP Client (Operator)**

On your **operator** (attacker) machine:

```sh
nix run .#client -- -connect "SERVER_IP:58008" -ignore-cert
```
- This connects you to the Ligolo-MP server’s operator port.

---

## 6. **Check Available Commands**

You can see all available options for each binary:
```sh
nix run .#server -- -help
nix run .#agent -- -help
nix run .#client -- -help
```

---

## 7. **Networking Notes**

- Make sure the server’s ports (default: 11601 and 58008) are open and reachable from agents and clients.
- You may need to adjust your firewall or security group settings.

---

## 8. **Logs and Troubleshooting**

- The server and agent will print logs to your terminal.
- If you want to run them in the background, use `tmux`, `screen`, or `nohup`.

---

## 9. **Example: All-in-One Test (on localhost)**

You can test everything on a single machine using different terminals:

**Terminal 1 (server):**
```sh
nix run .#server
```

**Terminal 2 (agent):**
```sh
nix run .#agent -- -connect "127.0.0.1:11601" -ignore-cert
```

**Terminal 3 (client):**
```sh
nix run .#client -- -connect "127.0.0.1:58008" -ignore-cert
```

---

## 10. **Stopping the Services**

- Just press `Ctrl+C` in the terminal where the process is running.

---

## 11. **Updating the Flake**

To update to the latest version (if your flake repo updates):
```sh
git pull
nix flake update
```

---

## 12. **Uninstalling**

- No installation is performed; just delete the `ligolo-mp-flake` directory when done.

---

## 13. **Security Note**

- For real deployments, use valid TLS certificates and **do not** use `-ignore-cert` in production.

---

**That’s it!**  
You can now use Ligolo-MP on any Linux system with Nix, without needing to install or configure anything system-wide.

---

If you need a **copy-paste cheat sheet** or have a specific scenario (multiple agents, custom ports, etc.), just ask!