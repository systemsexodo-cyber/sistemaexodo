-- Criar usuário
CREATE USER exodo_user WITH PASSWORD 'senha123';

-- Criar banco
CREATE DATABASE exodo_db OWNER exodo_user;

-- Conceder privilégios
GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
ALTER ROLE exodo_user CREATEDB;
