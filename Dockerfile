FROM ruby:2.7-alpine

ENV LANG C.UTF-8

WORKDIR /app

RUN apk --no-cache add \
  tzdata \
  build-base \
  libcurl \
  less

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

ENTRYPOINT ["./tgremind.rb"]
