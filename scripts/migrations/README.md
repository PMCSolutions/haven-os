# Migrations

One script per release that needs a one-off change on existing installs —
renaming a config file, removing a package, changing a default.

- Name it after the release it belongs to: `0.2.0.sh`
- `patch.sh` runs every migration newer than the installed version and not
  newer than the patch version, in version order.
- Scripts run as root and are `source`d in a subshell with `lib.sh` loaded,
  so `log`, `warn` and `HAVEN_ROOT` are available.
- Make them safe to run twice.

Releases that only change files in `rootfs/` or the package list don't need a
migration — `patch.sh` handles those automatically.
