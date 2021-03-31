FROM dependabot/dependabot-core

COPY dependabot-script dependabot-script
WORKDIR dependabot-script
RUN bundle install -j 3 --path vendor

COPY src/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
