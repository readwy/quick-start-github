FROM ubuntu:24.04

ENV PS1="[\u@claude \W]# "
ENV TZ="Asia/Shanghai"
ENV HOSTNAME=claude

RUN DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y curl wget jq python3-dev build-essential xz-utils git && rm -rf /var/lib/apt/lists/*
RUN curl -o /tmp/node-v24.15.0-linux-x64.tar.xz https://nodejs.org/dist/v24.15.0/node-v24.15.0-linux-x64.tar.xz
RUN curl -o /tmp/node-v22.22.2-linux-x64.tar.xz https://nodejs.org/dist/v22.22.2/node-v22.22.2-linux-x64.tar.xz
RUN curl -o /tmp/node-v20.20.2-linux-x64.tar.xz https://nodejs.org/dist/v20.20.2/node-v20.20.2-linux-x64.tar.xz
RUN wget --quiet -O /tmp/OpenJDK8U-jdk_x64_linux_hotspot_8u492b09.tar.gz https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u492-b09/OpenJDK8U-jdk_x64_linux_hotspot_8u492b09.tar.gz
RUN wget --quiet -O /tmp/OpenJDK11U-jdk_x64_linux_hotspot_11.0.31_11.tar.gz https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.31%2B11/OpenJDK11U-jdk_x64_linux_hotspot_11.0.31_11.tar.gz
RUN wget --quiet -O /tmp/OpenJDK17U-jdk_x64_linux_hotspot_17.0.19_10.tar.gz https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.19%2B10/OpenJDK17U-jdk_x64_linux_hotspot_17.0.19_10.tar.gz
RUN wget --quiet -O /tmp/OpenJDK21U-jdk_x64_linux_hotspot_21.0.11_10.tar.gz https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.11%2B10/OpenJDK21U-jdk_x64_linux_hotspot_21.0.11_10.tar.gz
RUN curl -o /tmp/apache-maven-3.6.3-bin.tar.gz https://archive.apache.org/dist/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz
RUN curl -o /tmp/apache-maven-3.8.9-bin.tar.gz https://archive.apache.org/dist/maven/maven-3/3.8.9/binaries/apache-maven-3.8.9-bin.tar.gz
RUN curl -o /tmp/apache-maven-3.9.15-bin.tar.gz https://archive.apache.org/dist/maven/maven-3/3.9.15/binaries/apache-maven-3.9.15-bin.tar.gz
RUN mkdir -p /opt/env/node
RUN mkdir -p /opt/env/java
RUN mkdir -p /opt/env/maven
RUN chmod 755 /opt/env
RUN tar -xf /tmp/node-v24.15.0-linux-x64.tar.xz -C /opt/env/node
RUN tar -xf /tmp/node-v22.22.2-linux-x64.tar.xz -C /opt/env/node
RUN tar -xf /tmp/node-v20.20.2-linux-x64.tar.xz -C /opt/env/node
RUN tar -zxf /tmp/OpenJDK8U-jdk_x64_linux_hotspot_8u492b09.tar.gz -C /opt/env/java
RUN tar -zxf /tmp/OpenJDK11U-jdk_x64_linux_hotspot_11.0.31_11.tar.gz -C /opt/env/java
RUN tar -zxf /tmp/OpenJDK17U-jdk_x64_linux_hotspot_17.0.19_10.tar.gz -C /opt/env/java
RUN tar -zxf /tmp/OpenJDK21U-jdk_x64_linux_hotspot_21.0.11_10.tar.gz -C /opt/env/java
RUN tar -zxf /tmp/apache-maven-3.6.3-bin.tar.gz -C /opt/env/maven
RUN tar -zxf /tmp/apache-maven-3.8.9-bin.tar.gz -C /opt/env/maven
RUN tar -zxf /tmp/apache-maven-3.9.15-bin.tar.gz -C /opt/env/maven
RUN rm -rf /tmp/node-v24.15.0-linux-x64.tar.xz
RUN rm -rf /tmp/node-v22.22.2-linux-x64.tar.xz
RUN rm -rf /tmp/node-v20.20.2-linux-x64.tar.xz
RUN rm -rf /tmp/OpenJDK8U-jdk_x64_linux_hotspot_8u492b09.tar.gz
RUN rm -rf /tmp/OpenJDK11U-jdk_x64_linux_hotspot_11.0.31_11.tar.gz
RUN rm -rf /tmp/OpenJDK17U-jdk_x64_linux_hotspot_17.0.19_10.tar.gz
RUN rm -rf /tmp/OpenJDK21U-jdk_x64_linux_hotspot_21.0.11_10.tar.gz
RUN rm -rf /tmp/apache-maven-3.6.3-bin.tar.gz
RUN rm -rf /tmp/apache-maven-3.8.9-bin.tar.gz
RUN rm -rf /tmp/apache-maven-3.9.15-bin.tar.gz
RUN curl -o /etc/profile.d/java.sh https://pub-308fdf0fa2bd4610abe7059fb335eb69.r2.dev/claude/java.sh
RUN curl -o /etc/profile.d/maven.sh https://pub-308fdf0fa2bd4610abe7059fb335eb69.r2.dev/claude/maven.sh
RUN curl -o /etc/profile.d/node.sh https://pub-308fdf0fa2bd4610abe7059fb335eb69.r2.dev/claude/node.sh
RUN . /etc/profile && npm install -g @anthropic-ai/claude-code
RUN npm install -g agent-browser
RUN agent-browser install --with-deps
RUN useradd -m dev -s /bin/bash && mkdir -p /home/dev/.claude
RUN echo "source /etc/profile" >> /home/dev/.bashrc && chown -R dev: /home/dev

USER dev

RUN . /etc/profile && \
RUN claude plugin marketplace add forrestchang/andrej-karpathy-skills
RUN claude plugin marketplace add obra/superpowers-marketplace
RUN claude plugin marketplace add https://github.com/affaan-m/everything-claude-code
RUN claude plugin marketplace add anthropics/skills
RUN claude plugin install andrej-karpathy-skills@karpathy-skills
RUN claude plugin install superpowers@superpowers-marketplace
RUN claude plugin install everything-claude-code@everything-claude-code
RUN claude plugin install document-skills@anthropic-agent-skills
RUN npx skills add google/skills -g -y
RUN npx skills add https://github.com/vercel-labs/agent-browser --skill agent-browser -g -y
RUN agent-browser skills get core --full
RUN npx skills add https://github.com/vercel-labs/skills --skill find-skills -g -y
RUN npx skills add https://github.com/anthropics/skills --skill skill-creator -g -y
RUN npx skills add https://github.com/nextlevelbuilder/ui-ux-pro-max-skill --skill ui-ux-pro-max -g -y
RUN npx skills add https://github.com/tanweai/pua --skill pua -g -y
RUN npx skills add https://github.com/anthropics/skills --skill frontend-design -g -y &
RUN jq '.hasCompletedOnboarding = true' /home/dev/.claude.json > /tmp/.claude.json && mv /tmp/.claude.json /home/dev/.claude.json
RUN jq '.env=(.env//{})|.env.ANTHROPIC_AUTH_TOKEN="ANTHROPIC_AUTH_TOKEN_PLACEHOLDER"|.env.ANTHROPIC_BASE_URL="ANTHROPIC_BASE_URL_PLACEHOLDER"|.env.HAIKU_MODEL="HAIKU_MODEL_PLACEHOLDER"|.env.OPUS_MODEL="OPUS_MODEL_PLACEHOLDER"|.env.SONNET_MODEL="SONNET_MODEL_PLACEHOLDER"' /home/dev/.claude/settings.json > /tmp/settings.json && mv /tmp/settings.json /home/dev/.claude/settings.json
RUN sed -i "s|ANTHROPIC_AUTH_TOKEN_PLACEHOLDER|"$CLAUDE_ANTHROPIC_AUTH_TOKEN"|g" /home/dev/.claude/settings.json
RUN sed -i "s|ANTHROPIC_BASE_URL_PLACEHOLDER|"$CLAUDE_ANTHROPIC_BASE_URL"|g" /home/dev/.claude/settings.json
RUN sed -i "s|HAIKU_MODEL_PLACEHOLDER|"$CLAUDE_HAIKU_MODEL"|g" /home/dev/.claude/settings.json
RUN sed -i "s|OPUS_MODEL_PLACEHOLDER|"$CLAUDE_OPUS_MODEL"|g" /home/dev/.claude/settings.json
RUN sed -i "s|SONNET_MODEL_PLACEHOLDER|"$CLAUDE_SONNET_MODEL"|g" /home/dev/.claude/settings.json

# image_name: claude1:v$(date "+%Y%m%d%H%M%S")
# docker build --tag registry.cn-hangzhou.aliyuncs.com/cases/claude:$(date "+%Y%m%d%H%M%S") .
# docker build --tag registry.cn-hangzhou.aliyuncs.com/cases/claude:20260430155304 .
# touch /apps/claude/.claude.json
# touch /apps/claude/settings.json
# mkdir -p /apps/claude/workspace
# chown -R 1001:1001 /apps/claude
# chown 1001:1001 /apps/claude/.claude.json
# chown 1001:1001 /apps/claude/settings.json
#
# docker run --rm -it --net=host \
# -e TZ=Asia/Shanghai \
# -v /apps/claude/.claude.json:/home/dev/.claude.json \
# -v /apps/claude/settings.json:/home/dev/.claude/settings.json \
# -v /apps/claude/workspace:/apps/claude/workspace \
# -w /apps/claude/workspace \
# registry.cn-hangzhou.aliyuncs.com/cases/claude:20260430155304 bash
#
# .claude.json
# {
#   "firstStartTime": "2026-04-30T13:23:44.288Z",
#   "opusProMigrationComplete": true,
#   "sonnet1m45MigrationComplete": true,
#   "migrationVersion": 12,
#   "userID": "78b5a1b58ea758b006807f9877cc1cf25121c74199c54b62fff65405c821fc5c",
#   "hasCompletedOnboarding": true
# }
#
# settings.json
# {
#   "env": {
#     "ANTHROPIC_AUTH_TOKEN": "sk-xxxx",
#     "ANTHROPIC_BASE_URL": "https://bgm66.de5.net",
#     "HAIKU_MODEL": "claude-haiku-4-7-thinking",
#     "OPUS_MODEL": "claude-opus-4-7-thinking",
#     "SONNET_MODEL": "claude-sonnet-4-7-thinking"
#   },
#   "autoUpdatesChannel": "latest",
#   "skipDangerousModePermissionPrompt": true,
#     "extraKnownMarketplaces": {
#       "karpathy-skills": {
#         "source": {
#           "source": "github",
#           "repo": "forrestchang/andrej-karpathy-skills"
#         }
#       }
#     },
#     "enabledPlugins": {
#       "andrej-karpathy-skills@karpathy-skills": true
#     }
# }
#