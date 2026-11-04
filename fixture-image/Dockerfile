# The smallest image that can be built, scanned and have a digest read back off it.
#
# FROM scratch is deliberate and the whole point of this fixture: the image carries no
# operating system and no packages, so the Trivy HIGH/CRITICAL gate in
# docker-hub-publish.yml finds nothing TODAY AND EVERY DAY AFTER. Any real base image
# would make this repository's required check fail the week a CVE is published against
# it, on a pull request that changed nothing.
FROM scratch

# Something to copy, so the build produces a layer and therefore a digest rather than an
# empty manifest.
COPY marker.txt /marker.txt
