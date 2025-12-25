```
      ___           ___           ___           ___           ___           ___           ___       ___       ___
     /\  \         /\  \         /\  \         /\  \         /\__\         /\  \         /\__\     /\__\     /\  \
    /::\  \       /::\  \       /::\  \       /::\  \       /:/  /        /::\  \       /:/  /    /:/  /    /::\  \
   /:/\ \  \     /:/\:\  \     /:/\:\  \     /:/\ \  \     /:/__/        /:/\:\  \     /:/  /    /:/  /    /:/\ \  \
  _\:\~\ \  \   /::\~\:\  \   /::\~\:\  \   _\:\~\ \  \   /::\  \ ___   /::\~\:\  \   /:/  /    /:/  /    _\:\~\ \  \
 /\ \:\ \ \__\ /:/\:\ \:\__\ /:/\:\ \:\__\ /\ \:\ \ \__\ /:/\:\  /\__\ /:/\:\ \:\__\ /:/__/    /:/__/    /\ \:\ \ \__\
 \:\ \:\ \/__/ \:\~\:\ \/__/ \/__\:\/:/  / \:\ \:\ \/__/ \/__\:\/:/  / \:\~\:\ \/__/ \:\  \    \:\  \    \:\ \:\ \/__/
  \:\ \:\__\    \:\ \:\__\        \::/  /   \:\ \:\__\        \::/  /   \:\ \:\__\    \:\  \    \:\  \    \:\ \:\__\
   \:\/:/  /     \:\ \/__/        /:/  /     \:\/:/  /        /:/  /     \:\ \/__/     \:\  \    \:\  \    \:\/:/  /
    \::/  /       \:\__\         /:/  /       \::/  /        /:/  /       \:\__\        \:\__\    \:\__\    \::/  /
     \/__/         \/__/         \/__/         \/__/         \/__/         \/__/         \/__/     \/__/     \/__/
```

<p align="center">
  <strong>Reusable Nix development shells</strong>
</p>

---

## Available Shells

| Shell | Description |
|-------|-------------|
| [cloud-auth](./shells/cloud-auth) | AWS, GCP, Azure authentication with fzf selector |

## Usage

```bash
# Use a specific shell
nix develop github:lov3g00d/seashells?dir=shells/cloud-auth

# With direnv
echo "use flake github:lov3g00d/seashells?dir=shells/cloud-auth" > .envrc
```

## Adding to Flake Registry

```nix
# In your NixOS/home-manager config
nix.registry.seashells.to = {
  type = "github";
  owner = "lov3g00d";
  repo = "seashells";
};
```

Then use:

```bash
nix develop seashells?dir=shells/cloud-auth
```

## Contributing

Add new shells under `shells/<name>/` with their own `flake.nix`.

## License

MIT
