FROM verdaccio/verdaccio:6.1.6@sha256:44af8dec4b8bfb9b940263f56ee5f371484515e4397eea56ab9c942500ab9dfa

COPY ./verdaccio.config /etc/verdaccio/conf/config.yaml
