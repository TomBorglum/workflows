# Changelog

## [2.0.1](https://github.com/TomBorglum/workflows/compare/v2.0.0...v2.0.1) (2026-11-13)


### Bug Fixes

* **docker-hub-publish:** require directories under compose-projects ([#30](https://github.com/TomBorglum/workflows/issues/30)) ([56d2491](https://github.com/TomBorglum/workflows/commit/56d24910fb829e1424cc31a6681d32b2b339c306))

## [2.0.0](https://github.com/TomBorglum/workflows/compare/v1.2.0...v2.0.0) (2026-11-13)


### ⚠ BREAKING CHANGES

* **docker-hub-publish:** the `image-directories`, `compose-directories`, `trivyignores`, `vex-documents` and `vulnerability-gate` inputs are removed. Declare them in the config file instead: `images.directories` keyed by directory, `compose-projects` keyed by directory, per-image `trivyignores` and `vex-documents` lists resolved against the image directory, and `images.gates.vulnerability`. A caller still passing a removed input fails with `Invalid input`. README.md documents every key.

### Features

* **docker-hub-publish:** declare images in a config file ([#21](https://github.com/TomBorglum/workflows/issues/21)) ([8be4c58](https://github.com/TomBorglum/workflows/commit/8be4c58f5571af4b16bf0649f5fa86b7736c5ccf))
* **docker-hub-publish:** report the suppressed findings on every run ([#25](https://github.com/TomBorglum/workflows/issues/25)) ([aa3e93c](https://github.com/TomBorglum/workflows/commit/aa3e93cf48bf718023f2306bedbba9165a07a9f0))
* **docker-hub-publish:** validate the config file against a JSON Schema ([#23](https://github.com/TomBorglum/workflows/issues/23)) ([cfb744e](https://github.com/TomBorglum/workflows/commit/cfb744e4b0d51d04644417fbf6b02b3fce2ed287))

## [1.2.0](https://github.com/TomBorglum/workflows/compare/v1.1.1...v1.2.0) (2026-11-12)


### Features

* **docker-hub-publish:** add vulnerability-gate and vex-documents inputs ([#19](https://github.com/TomBorglum/workflows/issues/19)) ([5b19b36](https://github.com/TomBorglum/workflows/commit/5b19b36f7c14ff00b80d7fde8f52b530a4879f6d))


### Dependencies

* Bump the actions group with 2 updates ([#17](https://github.com/TomBorglum/workflows/issues/17)) ([4108da3](https://github.com/TomBorglum/workflows/commit/4108da3e009cd9ab71076ef5526a22080eb2057b))

## [1.1.1](https://github.com/TomBorglum/workflows/compare/v1.1.0...v1.1.1) (2026-11-05)


### Dependencies

* update sonar scan ([#15](https://github.com/TomBorglum/workflows/issues/15)) ([52df4d1](https://github.com/TomBorglum/workflows/commit/52df4d11e8517640f84309fe81403860a32c1beb))

## [1.1.0](https://github.com/TomBorglum/workflows/compare/v1.0.2...v1.1.0) (2026-11-05)


### Features

* add docker-hub-publish workflow ([#10](https://github.com/TomBorglum/workflows/issues/10)) ([41a3bfd](https://github.com/TomBorglum/workflows/commit/41a3bfd28fd1e3f2db96ce6be4f4291579987ddc))

## [1.0.2](https://github.com/TomBorglum/workflows/compare/v1.0.1...v1.0.2) (2026-10-26)


### Dependencies

* Bump the actions group across 1 directory with 2 updates ([#8](https://github.com/TomBorglum/workflows/issues/8)) ([9fe8b97](https://github.com/TomBorglum/workflows/commit/9fe8b977015bf370e443ff373de8fc81ba3d904b))

## [1.0.1](https://github.com/TomBorglum/workflows/compare/v1.0.0...v1.0.1) (2026-10-16)


### Dependencies

* bump TomBorglum/actions to v3.0.0 and follow the renamed action paths ([#5](https://github.com/TomBorglum/workflows/issues/5)) ([8415dd7](https://github.com/TomBorglum/workflows/commit/8415dd743668c7ed8ecb770e6ef477a20aa6a5a7))

## 1.0.0 (2026-10-15)


### Features

* add update-pixi-dependencies workflow ([#3](https://github.com/TomBorglum/workflows/issues/3)) ([f84740e](https://github.com/TomBorglum/workflows/commit/f84740ecf146fd6a5f56c6aaf6422511f4f90710))
