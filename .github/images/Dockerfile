FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -q && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      gnupg \
      libbz2-dev \
      libffi-dev \
      liblzma-dev \
      libsqlite3-dev \
      libyaml-dev \
      locales \
      lsb-release \
      openjdk-17-jdk-headless \
      tzdata \
      zlib1g-dev \
  && ln -fs /usr/share/zoneinfo/UTC /etc/localtime \
  && dpkg-reconfigure --frontend noninteractive tzdata \
  && locale-gen en_US.UTF-8 fr_FR.UTF-8 \
  && update-locale \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /etc/apt/trusted.gpg.d/microsoft.gpg \
  && curl -fsSL https://packages.microsoft.com/config/ubuntu/22.04/prod.list \
      | tee /etc/apt/sources.list.d/mssql-release.list \
  && apt-get update -q \
  && ACCEPT_EULA=Y apt-get install -y --no-install-recommends \
      freetds-dev \
      libmysqlclient-dev \
      libpq-dev \
      mssql-tools18 \
      msodbcsql18 \
      unixodbc-dev \
  && echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' > /etc/profile.d/mssql-tools.sh \
  && rm -rf /var/lib/apt/lists/*

RUN apt-get update -q && apt-get install -y --no-install-recommends \
      postgresql \
      postgresql-contrib \
  && rm -rf /var/lib/apt/lists/* \
  && service postgresql start \
  && su postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD 'secret';\"" \
  && su postgres -c "createdb arelx_test" \
  && service postgresql stop

RUN apt-get update -q && apt-get install -y --no-install-recommends \
      mysql-server \
  && rm -rf /var/lib/apt/lists/* \
  && printf '[mysqld]\ncharacter-set-server = utf8mb4\ncollation-server = utf8mb4_general_ci\n' \
       > /etc/mysql/mysql.conf.d/utf8mb4.cnf \
  && service mysql start \
  && mysql -u root -e "CREATE DATABASE IF NOT EXISTS arelx_test CHARACTER SET utf8mb4;" \
  && service mysql stop

WORKDIR /workspace
