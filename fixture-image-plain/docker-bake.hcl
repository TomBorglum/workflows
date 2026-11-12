# What the fixture image IS, declared beside it exactly as a caller declares its own.
# docker-hub-publish.yml passes `source: fixture-image-plain` and loads this file, so paths
# resolve against THIS directory.

# The target name is fixed by the workflow: its `bake-target: image` and `targets: image`
# both name `image`, and a bake file declaring anything else fails the build.
target "image" {
  # `.` rather than `..`, unlike a real service: a context that leaves this directory
  # needs `--allow=fs.read=..`, and a fixture has no reason to need it.
  context    = "."
  dockerfile = "Dockerfile"

  labels = {
    "org.opencontainers.image.title"       = "workflows-fixture-image-plain"
    "org.opencontainers.image.description" = "Build fixture for the docker-hub-publish caller test."
  }

  annotations = [
    "manifest:org.opencontainers.image.title=workflows-fixture-image-plain",
    "manifest:org.opencontainers.image.description=Build fixture for the docker-hub-publish caller test.",
  ]
}
