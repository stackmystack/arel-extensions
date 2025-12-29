FROM ubuntu:24.04

ENV APP_HOME=/app
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV MISE_DATA_DIR="/mise"
ENV MISE_CONFIG_DIR="/mise"
ENV MISE_CACHE_DIR="/mise/cache"
ENV MISE_INSTALL_PATH="/usr/local/bin/mise"
ENV PATH="/mise/shims:$PATH"

RUN mkdir -p $APP_HOME

# Install system and dev ependencies
RUN apt-get update -q && apt-get install -y \
  curl eza fd-find bundler build-essential git gnupg locales \
  libbz2-dev libffi-dev liblzma-dev lsb-release libsqlite3-dev libyaml-dev \
  make neovim ncurses-term pkg-config openjdk-17-jdk-headless tzdata zlib1g-dev \
  && ln -fs /usr/share/zoneinfo/UTC /etc/localtime \
  && dpkg-reconfigure --frontend noninteractive tzdata

RUN curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
  && echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" | tee  /etc/apt/sources.list.d/pgdg.list \
  && curl https://packages.microsoft.com/keys/microsoft.asc | tee /etc/apt/trusted.gpg.d/microsoft.asc \
  && curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list | tee /etc/apt/sources.list.d/mssql-release.list \
  && apt-get update -q

RUN ACCEPT_EULA=y DEBIAN_FRONTEND=noninteractive apt-get install -y \
  freetds-dev libmysqlclient-dev mysql-client msodbcsql18 mssql-tools18 unixodbc-dev libpq-dev libssl-dev\
  && echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && locale-gen en_US.UTF-8

WORKDIR $APP_HOME

# Install rubies
RUN curl https://mise.run | sh
COPY mise.toml .
RUN mise trust && mise install

# Patch
RUN sed -i '1s|^#!\s*/bin/sh|#!/usr/bin/env bash|' /mise/installs/ruby/jruby-9.2/bin/jruby.sh

# Configure atuin
RUN mkdir -p ~/.config/atuin && \
    cat <<TOML > ~/.config/atuin/config.toml
dialect = "uk"
style = "compact"
inline_height = 16
invert = true
enter_accept = true
TOML

# Setup shell
RUN cat <<BASH >> ~/.bashrc
alias diff='git diff --no-index -u --ws-error-highlight=all --color=always'
alias fd='fd -H'
alias g='git'
alias ls='eza --all --color=auto --git --group-directories-first --header --hyperlink --icons=auto --long --mounts --no-permissions --no-user --octal-permissions --sort=name --time-style=relative -F'
alias ssh='ssh -o "SetEnv TERM=xterm-256color"'
alias y='yazi'

eval "\$(atuin init bash --disable-up-arrow)"
BASH

# for java+mssql
RUN curl -LO https://github.com/microsoft/mssql-jdbc/releases/download/v8.4.1/mssql-jdbc-8.4.1.jre11.jar
