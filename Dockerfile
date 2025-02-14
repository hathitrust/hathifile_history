FROM ruby:3.1

RUN apt-get update -yqq && apt-get install -yqq --no-install-recommends

WORKDIR /usr/src/app
ENV BUNDLE_PATH /gems
RUN gem install bundler
