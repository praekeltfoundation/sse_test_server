###############
# Build stage #
###############

FROM elixir:1.6-alpine AS builder

WORKDIR /build

# We need hex and rebar build tools installed.
RUN mix local.hex --force && mix local.rebar --force

# Copy all the source files. We can't just use `COPY . .` because that would
# also copy deps, _build, and various other things that would cause trouble
# with the build. Also, `COPY dir .` will copy the contents of the dir instead
# of the dir itself, so we have to manually copy each dir into its own
# destination.
COPY mix.* ./
COPY config ./config
COPY lib ./lib
COPY test ./test
COPY rel ./rel

# Build the release to put in the next image.
ENV MIX_ENV=prod
RUN mix deps.get
RUN mix compile
RUN mix release --env=prod


###############
# Image stage #
###############

# We don't actually need Erlang/Elixir installed, because it's all included in
# the release package. Thus, we start from the base alpine image.
FROM alpine:3.7

# We need bash for the generated scripts, tini for signal propagation, and
# openssl for crypto.
RUN apk add --no-cache bash tini openssl

WORKDIR /app

# Get the release we built earlier from the build container.
COPY --from=builder /build/_build/prod/rel/sse_test_server/ ./

# We need runtime write access to /app/var as a non-root user.
RUN addgroup -S sts && adduser -S -g sts -h /app sts
RUN mkdir var && chown sts var

# Run as non-root.
USER sts

# REPLACE_OS_VARS lets us use envvars to configure some runtime parameters.
# Currently we only support using $ERLANG_COOKIE to set the cookie.
ENV REPLACE_OS_VARS=true

# Signals are swallowed by the pile of generated scripts that run the app, so
# we need tini to manage them.
ENTRYPOINT ["tini", "--"]

# By default, run our application in the foreground.
CMD ["./bin/sse_test_server", "foreground"]
