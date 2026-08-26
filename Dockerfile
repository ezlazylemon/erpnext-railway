# ------------------------------------------
# Stage 01 — builder
# Source: pipech/erpnext-docker-debian (Railway pattern)
# ------------------------------------------
FROM pipech/erpnext-docker-debian:version-15-latest AS builder

USER $systemUser
WORKDIR /home/$systemUser/$benchFolderName

RUN echo "-> Start builder" \
    && rm -rf /home/$systemUser/$benchFolderName/sites/site1.local \
    # IPv6 hotfix — Railway private networking is IPv6-only
    # https://docs.railway.com/guides/private-networking#caveats
    && sed -i 's/socket\.AF_INET, socket\.SOCK_STREAM/socket.AF_INET6, socket.SOCK_STREAM/g' /home/frappe/bench/apps/frappe/frappe/utils/connections.py \
    && echo "-> Builder done"

# ------------------------------------------
# Stage 02 — production runtime
# ------------------------------------------
FROM frappe/bench:v5.22.9

ENV systemUser=frappe
ENV benchFolderName=bench

COPY --from=builder --chown=$systemUser /home/$systemUser/$benchFolderName /home/$systemUser/$benchFolderName
# venv бенча ссылается на python из pyenv builder-образа; без копии pyenv
# симлинк env/bin/python бьётся и bench build падает FileNotFoundError
COPY --from=builder --chown=$systemUser /home/$systemUser/.pyenv /home/$systemUser/.pyenv

COPY temp_nginx.conf /home/$systemUser/temp_nginx.conf
COPY temp_supervisor.conf /home/$systemUser/temp_supervisor.conf

# --- Custom Russian translations (APORT) --------------------------------------
# v15 читает переводы из apps/<app>/translations/ru.csv.
# Наши CSV = сток + вычитанные строки (13.7k erpnext, 4.7k frappe).
# ВАЖНО: записи доктайпа Translation в БАЗЕ имеют приоритет над файлами.
COPY --chown=$systemUser translations/erpnext-ru.csv /home/$systemUser/$benchFolderName/apps/erpnext/erpnext/translations/ru.csv
COPY --chown=$systemUser translations/frappe-ru.csv /home/$systemUser/$benchFolderName/apps/frappe/frappe/translations/ru.csv

USER root
WORKDIR /home/$systemUser/$benchFolderName

ARG DEBIAN_FRONTEND=noninteractive

RUN echo "-> Install nginx, supervisor, mariadb-client, gettext-base, netcat" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        nginx \
        supervisor \
        mariadb-client \
        gettext-base \
        netcat-openbsd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && echo "-> Remove nginx default site" \
    && rm /etc/nginx/sites-enabled/default \
    && echo "-> Rebuild bench (compile assets)" \
    && su $systemUser -c "bench build" \
    && echo "-> Snapshot built sites for first-boot assets/apps links" \
    && su $systemUser -c "cp -r /home/$systemUser/$benchFolderName/sites /home/$systemUser/$benchFolderName/built_sites"

COPY --chown=$systemUser --chmod=0755 railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY --chown=$systemUser --chmod=0755 railway-cmd.sh /usr/local/bin/railway-cmd.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["/usr/local/bin/railway-cmd.sh"]

EXPOSE 80
