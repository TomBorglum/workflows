# Schema rejection fixtures

Every file here is a config file `schema/docker-hub-publish.json` must refuse.
`_test-docker-hub-publish.yml`'s `schema` job fails if any is accepted.

One file per rule family, named after the rule. No file carries a second defect: a fixture
that fails for two reasons stops proving anything about either once one rule changes.

Add a file here with every rule added to the schema.
