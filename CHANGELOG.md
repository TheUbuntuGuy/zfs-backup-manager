## v0.0.2
- Fixed bug where a failure in the local ZFS send command would not return a failure status
- Added support for configuration files (no longer need to edit the script header to change settings)
- Removed restriction that "root" mode can only be used on top level datasets (useful in case of nested root filesystem i.e. pool/ROOT/realroot)
- Added Debian packaging via a Makefile
- Various cleanup in accordance to shellcheck linting
- Added GitLab CI pipeline for linting and package build (using public Docker images)

## v0.0.1
- Initial release
