# Schema rejection fixtures

Every file here is a `docker-hub-publish` config file that `schema/docker-hub-publish.json`
must refuse. `_test-docker-hub-publish.yml`'s `schema` job validates each one and fails if any
is accepted.

They exist because a schema's whole job is refusing things, and nothing else in this
repository proves it still does. A rule weakened by a later edit — an `additionalProperties`
dropped, a pattern loosened — leaves every other test green.

One file per rule family, named after the rule. No file carries a second defect: a fixture
that fails for two reasons stops proving anything about either once one rule changes.

Add a file here with every rule added to the schema.
