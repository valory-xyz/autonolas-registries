FROM ubuntu:20.04
RUN apt-get update && apt-get install -y sudo curl 

RUN groupadd -r newuser && useradd -r -g newuser newuser
RUN adduser newuser sudo
RUN adduser --disabled-password \
--gecos '' docker
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> \
/etc/sudoers
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash -
RUN apt-get install -y nodejs
RUN apt-get install -y gcc g++ make
RUN curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | tee /usr/share/keyrings/yarnkey.gpg >/dev/null
RUN echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt-get update && apt-get install -y yarn
RUN apt-get install -y git

COPY . /usr/src/app

WORKDIR /usr/src/app

RUN yarn install --non-interactive  --frozen-lockfile --ignore-engines

COPY $PWD/entrypoint.sh /usr/local/bin

ENTRYPOINT ["/bin/sh", "/usr/local/bin/entrypoint.sh"]