# Dockerfile para Google Cloud Run
FROM php:8.1-apache

# Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    libxml2-dev \
    libcurl4-openssl-dev \
    libzip-dev \
    libssl-dev \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Instalar extensões PHP necessárias para SPED-NFe
RUN docker-php-ext-install \
    xml \
    curl \
    zip \
    soap \
    mbstring \
    opcache

# Habilitar extensão OpenSSL (já vem habilitada)
RUN docker-php-ext-configure openssl --with-openssl && \
    docker-php-ext-install openssl

# Instalar Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Configurar diretório de trabalho
WORKDIR /var/www/html

# Copiar arquivos do projeto
COPY . .

# Instalar dependências do Composer
RUN composer install --no-dev --optimize-autoloader --no-interaction

# Criar diretórios necessários
RUN mkdir -p storage/certs storage/xml logs && \
    chmod -R 755 storage logs

# Configurar Apache para Cloud Run
RUN a2enmod rewrite && \
    a2enmod headers

# Configurar PHP para Cloud Run (porta 8080)
RUN echo "Listen 8080" > /etc/apache2/ports.conf && \
    sed -i 's/Listen 80/Listen 8080/' /etc/apache2/sites-available/000-default.conf && \
    sed -i 's/:80/:8080/' /etc/apache2/sites-available/000-default.conf

# Configurar variáveis de ambiente do PHP
ENV APACHE_DOCUMENT_ROOT=/var/www/html
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf && \
    sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Expor porta 8080 (requisito do Cloud Run)
EXPOSE 8080

# Comando para iniciar Apache
CMD ["apache2-foreground"]











