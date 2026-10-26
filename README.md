# dt-compose-commons

Environment with common configuration of an instance of \compose\ for Duckietown.

## PHP 7.4 security package build

The `php-packages` Docker target rebuilds the signed-APT Focal source
`php7.4=7.4.3-4ubuntu2.29` with the PHP2Shell backport from upstream commit
[`712e60f9edfd03f0960fc4fc3c2c375f42b90aa2`](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2).
The [patch](assets/patches/php2shell-712e60f9.patch) is vendored verbatim so builds
do not depend on GitHub's generated patch formatting. The Dockerfile verifies
its pinned SHA-256, checks the hunks already present in Focal, and applies the
remaining hunks with zero fuzz.

Build the packages without requiring a released Compose image:

```sh
docker buildx build --load --target php-packages \
  --build-arg ARCH=arm64v8 --build-arg DISTRO=ente \
  --build-arg DOCKER_REGISTRY=docker.io \
  --build-arg BASE_REPOSITORY=dt-legacy-py38-environment \
  -t compose-php74-packages:local .
```

Use `ARCH=amd64` for x86-64. Package compilation uses `nproc` to select the
available CPU count. Debian's historical test suite remains disabled with
`nocheck`; a successful package build is not a claim that the full suite passes.
The resulting package version is
`7.4.3-4ubuntu2.29+duckietown1.php2shell.712e60f9`.

The complete runtime image still requires a published security release from
[Compose #6](https://github.com/duckietown/compose/pull/6). The current
`COMPOSE_VERSION=1.3.5` default predates its guard and configuration files.
Publish the matching security image and pin its real release before merging
this PR; the package target above does not remove that release gate.
This backport is a limited mitigation for EOL PHP 7.4, not ongoing security
support or compatibility with the separate PHP 8/JWT application migration.
