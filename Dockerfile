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
    && echo "-> Get additional apps (baked into image)" \
    # ветки под frappe v15: hrms=version-15, insights=version-3,
    # crm/helpdesk живут на main (совместимы с v15 на момент фиксации)
    && bench get-app --branch version-15 --skip-assets hrms https://github.com/frappe/hrms \
    && bench get-app --branch version-3 --skip-assets insights https://github.com/frappe/insights \
    && bench get-app --skip-assets crm https://github.com/frappe/crm \
    && bench get-app --skip-assets helpdesk https://github.com/frappe/helpdesk \
    && echo "-> Builder done"

# ------------------------------------------
# Stage 02 — production runtime
# ------------------------------------------
FROM frappe/bench:v5.22.9

ENV systemUser=frappe
ENV benchFolderName=bench

COPY --from=builder --chown=$systemUser /home/$systemUser/$benchFolderName /home/$systemUser/$benchFolderName

COPY temp_nginx.conf /home/$systemUser/temp_nginx.conf
COPY temp_supervisor.conf /home/$systemUser/temp_supervisor.conf

# --- Custom Russian translations (APORT) --------------------------------------
# Заменяем машинный русский перевод на вычитанный. Файлы читаются приложениями
# из apps/<app>/translations/ru.csv; COPY стоит до `bench build`, чтобы сборка
# ассетов подхватила их. Правки перевода = коммит в translations/*.csv.
# ВАЖНО: записи доктайпа Translation в БАЗЕ имеют приоритет над этими файлами.
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
