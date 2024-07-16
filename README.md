# Waybar Wise FX Rate

Waybar module to get the FX rate between two currencies using the Wise API.

Example output in Waybar:
```
17.62 USD/MXN
```

## Getting Started

### Get your Wise API Key

In order for this to work, you need to provide your Wise API Key.

1. Log in to wise.
1. Go to: Profile -> Settings -> Developer tools -> API tokens.
1. Add new token
      1. _Name_: Waybar Wise FX Rate.
      1. _Token permissions_: **Read only** <- Very important!!
      1. Click _Create token_.
1. Copy your token

### Compile and install the binary

```sh
# Clone the repo
git clone https://github.com/rlopzc/waybar-wise-fx-rate.git

cd waybar-wise-fx-rate

# Build the binary
zig build --release=fast
```

The binary will be in `zig-out/bin/waybar-wise-fx-rate`.

Symlink it to your `~/.local/bin`. Replace `<your-path-to-project-dir>` with the dir where you cloned the repository.

```sh
ln -s $HOME/<path-to-project-dir>/zig-out/bin/waybar-wise-fx-rate ~/.local/bin/waybar-wise-fx-rate
```

### Downloading binary from Releases

Currently built for:
- x86_64-linux
- aarch64-linux
- arm-linux

1. Check your architecture.
1. Download it with `curl -L https://github.com/rlopzc/waybar-wise-fx-rate/releases/latest/download/waybar-wise-fx-rate-x86_64-linux > waybar-wise-fx-rate`.
1. Make it executable `chmod +x ./waybar-wise-fx-rate`.
1. Symlink it with: `ln -s $HOME/<download-dir>/waybar-wise-fx-rate ~/.local/bin/waybar-wise-fx-rate`.

> Replace the architecture with yours.

## Using the Waybar module

**CLI Arguments**.

- `--apikey`. Wise API key.
- `--source`. Source Currency supported by Wise.
- `--target`. Target Currency supported by Wise.

Add a custom module to your waybar config:

```json
"custom/wise-fx-rate": {
  "format": "{} {icon}",
  "return-type": "json",
  "format-icons": {
    "default": ""
  },
  "exec": "waybar-wise-fx-rate --apikey <wise-api-key> --source <source> --target <target>",
  "interval": 60
}
```
