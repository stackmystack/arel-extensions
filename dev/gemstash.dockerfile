FROM ruby:4-slim

# Install OS dependencies needed to build native gems (sqlite3)
RUN apt update \
  && apt install -y  build-essential curl libsqlite3-dev pkg-config \
  && apt clean \
  && rm -rf /var/lib/apt/lists/*

# Install gemstash
RUN gem install gemstash --no-document

# Create gemstash data dir
RUN mkdir -p /root/.gemstash

EXPOSE 9292

CMD ["gemstash", "start"]
