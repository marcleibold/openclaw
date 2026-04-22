# TODO

## Completed

- [x] Headless Chromium browser and gh CLI installed in openclaw container via init container
  - Both `gh` CLI and `chromium` binary available in `/opt/tools/`
  - LD_LIBRARY_PATH configured to find chromium's shared libraries
  - chromium runs in headless mode with `--no-sandbox`
