# Vendored Krohnkite

`krohnkite-0.9.11.3.kwinscript` is the Plasmarchy Krohnkite fork build from:

- Project: https://github.com/XelorR/Krohnkite
- Tag: `0.9.11.3`
- Asset: `dist/krohnkite.kwinscript`
- SHA256: `4eeddce1377bb89518ba9e1577d90411094e4346dc1820233faafad073ee66e9`

The fork adds the Hyprland-compatible `DwindleLayout`, which is Plasmarchy's
default layout.  The upstream project remains
https://codeberg.org/anametologin/Krohnkite; the fork syncs from it.

Krohnkite is MIT-licensed.  The archive is kept here so a fresh machine can be
deployed offline and reproducibly.  `deploy.sh` verifies this checksum before
installing the archive with `kpackagetool6`.

The same file is published at:

```
https://raw.githubusercontent.com/XelorR/Krohnkite/0.9.11.3/dist/krohnkite.kwinscript
https://raw.githubusercontent.com/XelorR/Krohnkite/master/dist/krohnkite.kwinscript
```

To update the fork build:

1. bump the version and tag the Krohnkite fork;
2. run `make clean && make package` there and copy the archive to
   `dist/krohnkite.kwinscript`;
3. update `KROHNKITE_DEFAULT_VERSION` in `scripts/deploy.sh`;
4. replace the file in this directory and regenerate `SHA256SUMS`:
   `(cd vendor && sha256sum krohnkite-<version>.kwinscript > SHA256SUMS)`.
