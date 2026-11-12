# The second image fixture. It carries no suppressions.
#
# docker-hub-publish.yml declares trivyignores and vex-documents per image directory. One image
# declaring them and one declaring none proves each matrix leg gets its own paths rather than
# the union of every image's. fixture-image is the one that declares them; this is the one that
# does not.
#
# FROM scratch for the reason fixture-image/Dockerfile gives: no operating system and no
# packages, so the HIGH/CRITICAL gate finds nothing today and every day after.
FROM scratch

# Something to copy, so the build produces a layer and therefore a digest rather than an
# empty manifest.
COPY marker.txt /marker.txt

# Declared for the reason fixture-image/Dockerfile gives: a scratch image otherwise
# defaults to root, which SonarCloud flags.
USER 65532:65532
