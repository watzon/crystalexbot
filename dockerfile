FROM crystallang/crystal:0.30.1
MAINTAINER cawatson1993@gmail.com
WORKDIR /app

# copy all your app files/directories to image 
COPY src ./src
COPY shard.yml ./shard.yml

# install crystal deps
RUN shards install
RUN crystal build --release ./src/crystalexbot.cr -o ./bot

# start the bot
CMD ./bot