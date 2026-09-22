# The custom agent runtime: a dungeon master with no state and no credential.
#
# Alpine plus python3 and nothing else. The application is standard library
# only, so there are no wheels to cross-build for the guest and nothing is
# fetched at run time.
#
# The label is what the host reads to decide whether this image will run at
# all: it names the oldest AgentGuard the application is willing to be started
# by.
FROM --platform=linux/arm64 alpine:3.20

RUN apk add --no-cache python3

COPY dungeon.py /app/dungeon.py

LABEL dev.jozu.agentguard.min-version=0.1.0

# The model this application asks for, by module name. Which upstream that
# reaches, with which credential and under which real model name, is the agent
# definition's business and is decided outside this image.
ENV DUNGEON_MODEL=dungeon-master

WORKDIR /app

# -u because the player is typing at this program. A buffered stdout would show
# the whole turn at once, after the fact, which is no use on stage.
ENTRYPOINT ["python3", "-u", "/app/dungeon.py"]
