FROM php:7.1-fpm-stretch

ENV php_conf /usr/local/etc/php-fpm.conf
ENV fpm_conf /usr/local/etc/php-fpm.d/www.conf
ENV php_vars /usr/local/etc/php/conf.d/docker-vars.ini

RUN APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 \
    && apt-get update && apt-get install -y --no-install-recommends \
        curl \
        gnupg2 \
        ca-certificates \
        lsb-release \
        bash \
        libmcrypt-dev \
        libpng-dev \
        curl \
        wget \
        git \
        supervisor \
        libxslt-dev \
        libjpeg-dev \
        libpq-dev \
        libmemcached-dev \
        libgeos-dev \
    && rm -rf /var/lib/apt/lists/*

RUN echo "deb http://nginx.org/packages/debian `lsb_release -cs` nginx" \
        | tee /etc/apt/sources.list.d/nginx.list \
    && curl -fsSL https://nginx.org/keys/nginx_signing.key | apt-key  add -  \
    && apt-key fingerprint ABF5BD827BD9BF62 \
    && apt-get update && apt-get install -y --no-install-recommends nginx \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd \
        --with-gd \
        --with-png-dir=/usr/include/ \
        --with-jpeg-dir=/usr/include

RUN docker-php-ext-install bcmath \
    pdo \
    pdo_mysql \
    iconv \
    mysqli \
    mbstring \
    mcrypt \
    gd \
    exif \
    xsl \
    json \
    soap \
    dom \
    zip \
    opcache

# Install Memcached for php
RUN curl -L -o /tmp/memcached.tar.gz "https://github.com/php-memcached-dev/php-memcached/archive/php7.tar.gz" \
    && mkdir -p /usr/src/php/ext/memcached \
    && tar -C /usr/src/php/ext/memcached -zxvf /tmp/memcached.tar.gz --strip 1 \
    && docker-php-ext-configure memcached \
    && docker-php-ext-install memcached \
    && rm /tmp/memcached.tar.gz

# Install php-Geos
RUN curl -L -o /tmp/php-geos.tar.gz "https://github.com/libgeos/php-geos/archive/master.tar.gz" \
    && mkdir -p /usr/src/php/ext/php-geos \
    && tar -C /usr/src/php/ext/php-geos -zxvf /tmp/php-geos.tar.gz --strip 1 \
    && docker-php-ext-configure php-geos \
    && docker-php-ext-install php-geos \
    && rm /tmp/php-geos.tar.gz

RUN pecl install xdebug \
    && pecl install redis \
    && docker-php-source delete \
    && mkdir -p /etc/nginx \
    && mkdir -p /var/www/app \
    && mkdir -p /run/nginx \
    && mkdir -p /var/log/supervisor \
    && EXPECTED_COMPOSER_SIGNATURE=$(wget -q -O - https://composer.github.io/installer.sig) \
    && php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php -r "if (hash_file('SHA384', 'composer-setup.php') === '${EXPECTED_COMPOSER_SIGNATURE}') { echo 'Composer.phar Installer verified'; } else { echo 'Composer.phar Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" \
    && php composer-setup.php --install-dir=/usr/bin --filename=composer \
    && php -r "unlink('composer-setup.php');"

# install nodejs
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash - \
    && apt-get install nodejs -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g gulp

# Uncomment this part if you need pip
# RUN apt-get install -y python-pip \
#        && pip install -U pip

# nginx site conf
ADD conf/supervisord.conf /etc/supervisord.conf
RUN rm -Rf /etc/nginx/nginx.conf
ADD conf/nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /etc/nginx/sites-available/ \
        && mkdir -p /etc/nginx/sites-enabled/ \
        && mkdir -p /etc/nginx/ssl/ \
        && rm -Rf /var/www/* \
        && mkdir -p /var/www/html/public
ADD conf/nginx-site.conf /etc/nginx/sites-available/default.conf
RUN ln -s /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf

# tweak php-fpm config
RUN echo "cgi.fix_pathinfo=1" > ${php_vars} \
        && echo "upload_max_filesize = 100M"  >> ${php_vars} \
        && echo "post_max_size = 100M"  >> ${php_vars} \
        && echo "variables_order = \"EGPCS\""  >> ${php_vars} \
        && echo "memory_limit = -1"  >> ${php_vars} \
    && sed -i \
        -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" \
        -e "s/pm.max_children = 5/pm.max_children = 4/g" \
        -e "s/pm.start_servers = 2/pm.start_servers = 3/g" \
        -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" \
        -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" \
        -e "s/;pm.max_requests = 500/pm.max_requests = 200/g" \
        -e "s/user = www-data/user = nginx/g" \
        -e "s/group = www-data/group = nginx/g" \
        -e "s/;listen.mode = 0660/listen.mode = 0666/g" \
        -e "s/;listen.owner = www-data/listen.owner = nginx/g" \
        -e "s/;listen.group = www-data/listen.group = nginx/g" \
        -e "s/^;clear_env = no$/clear_env = no/" \
        ${fpm_conf}

ADD conf/start.sh /start.sh
RUN chmod 755 /start.sh

ENV WEBROOT=/var/www/html

EXPOSE 80

CMD ["/start.sh"]
