# BGP

[![CI](https://github.com/lucacorti/bgp/actions/workflows/test.yml/badge.svg)](https://github.com/lucacorti/bgp/actions/workflows/test.yml)

A work-in-progress Border Gateway Protocol (BGP) implementation in Elixir.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `bgp` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:bgp, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/bgp](https://hexdocs.pm/bgp).

## Getting started

### Docker Compose

Docker Compose is used to simplify development and components installation and configurations.
Makefile is used as a wrapper around docker-compose commands.
Some commands are aliases around mix aliases, just to avoid boring and repetitive commands. 

#### Make commands

```bash
build                          Build all services containers
delete                         Delete all containers, images and volumes
halt                           Shoutdown all services containers
shell                          Enter into bgp service
start                          Start application
test                           Execute test suite
up                             Start all services
```

#### Build environment and start all services

```bash
make up
```

#### Start the project

```bash
make start
```

#### Destroy environment

```bash
make delete
```

