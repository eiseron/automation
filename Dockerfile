FROM ruby:3.3-slim-bookworm@sha256:dc786a8d54e07c9d0a6654db25d7ed5b68a43a694698d0fdc0c0236750c3a01b

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

ARG PG_MAJOR=18

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        git \
        ca-certificates \
        curl \
        cron \
        age \
    && install -d /usr/share/postgresql-common/pgdg && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc && \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends "postgresql-client-${PG_MAJOR}" && \
    rm -rf /var/lib/apt/lists/*

COPY . /src
RUN cd /src && \
    gem build eiseron_automation.gemspec && \
    gem install ./eiseron_automation-*.gem --no-document && \
    gem install aws-sdk-s3 --no-document && \
    gem cleanup && \
    rm -rf /src

WORKDIR /workspace

CMD ["eiseron"]
