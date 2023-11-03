FROM ruby:3.2

# bin/wait-for depends on netcat
RUN apt-get update -yqq && apt-get install -yqq --no-install-recommends \
  netcat-traditional

WORKDIR /usr/src/app
ENV BUNDLE_PATH /gems
RUN gem install bundler
