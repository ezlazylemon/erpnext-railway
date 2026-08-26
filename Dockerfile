# ------------------------------------------
# Stage 01 — builder
# Source: pipech/erpnext-docker-debian (Railway pattern)
# ------------------------------------------
FROM pipech/erpnext-docker-debian:version-16-latest AS builder

USER $systemUser
WORKDIR /home/$systemUser/$benchFolderName

RUN echo "-> Start builder" \
    && rm -rf /home/$systemUser/$benchFolderName/sites/site1.local \
    # IPv6 hotfix — Railway private networking is IPv6-only
    # https://docs.railway.com/guides/private-networking#caveats
    && sed -i 's/socket\.AF_INET, socket\.SOCK_STREAM/socket.AF_INET6, socket.SOCK_STREAM/g' /home/frappe/bench/apps/frappe/frappe/utils/connections.py \
    && echo "-> Upgrade Node to 22 (v16 era; CRM/Helpdesk need >=20)" \
    && export NVM_DIR="${NVM_DIR:-$HOME/.nvm}" \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install 22 \
    && nvm alias default 22 \
    && npm install -g yarn \
    && node -v && yarn -v \
    && echo "-> Get additional apps (baked into image)" \
    # ветки под frappe v15: hrms=version-15, insights=version-3,
    # crm/helpdesk живут на main (совместимы с v15 на момент фиксации)
    && bench get-app --branch version-16 --skip-assets hrms https://github.com/frappe/hrms \
    && bench get-app --branch version-3 --skip-assets insights https://github.com/frappe/insights \
    && bench get-app --skip-assets crm https://github.com/frappe/crm \
    && bench get-app --skip-assets helpdesk https://github.com/frappe/helpdesk \
    && echo "-> Builder done"

# ------------------------------------------
# Stage 02 — production runtime
# ------------------------------------------
FROM frappe/bench:v5.31.0

ENV systemUser=frappe
ENV benchFolderName=bench

COPY --from=builder --chown=$systemUser /home/$systemUser/$benchFolderName /home/$systemUser/$benchFolderName

COPY temp_nginx.conf /home/$systemUser/temp_nginx.conf
COPY temp_supervisor.conf /home/$systemUser/temp_supervisor.conf

# --- Custom Russian translations (APORT) --------------------------------------
# v16 читает переводы ТОЛЬКО из locale/<lang>.po (CSV больше не читается).
# Наши .po = поставочный словарь v16 + вычитанные переводы поверх.
# Правки перевода = коммит в translations/*-ru.po.
# ВАЖНО: записи доктайпа Translation в БАЗЕ имеют приоритет над файлами.
COPY --chown=$systemUser translations/erpnext-ru.po /home/$systemUser/$benchFolderName/apps/erpnext/erpnext/locale/ru.po
COPY --chown=$systemUser translations/frappe-ru.po /home/$systemUser/$benchFolderName/apps/frappe/frappe/locale/ru.po

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
    && echo "-> Rebuild bench (compile assets, Node 22)" \
    && su $systemUser -c 'export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"; . "$NVM_DIR/nvm.sh"; nvm install 22; nvm alias default 22; npm install -g yarn; node -v; yarn -v; bench build' \
    && echo "-> Snapshot built sites for first-boot assets/apps links" \
    && su $systemUser -c "cp -r /home/$systemUser/$benchFolderName/sites /home/$systemUser/$benchFolderName/built_sites"

COPY --chown=$systemUser --chmod=0755 railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY --chown=$systemUser --chmod=0755 railway-cmd.sh /usr/local/bin/railway-cmd.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["/usr/local/bin/railway-cmd.sh"]

EXPOSE 80
