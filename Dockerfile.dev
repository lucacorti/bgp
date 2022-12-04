FROM elixir:1.14-slim

RUN apt update && \
    apt install -y --no-install-recommends curl ssh git

RUN mix local.hex --force && mix local.rebar --force

ENV ERL_AFLAGS "-kernel shell_history enabled"
