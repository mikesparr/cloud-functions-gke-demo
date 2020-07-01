CREATE DATABASE IF NOT EXISTS `test1`;
USE `test1`;

CREATE TABLE IF NOT EXISTS users (id INT NOT NULL AUTO_INCREMENT, name VARCHAR(64) NULL, PRIMARY KEY (id));

INSERT INTO users (name) VALUES ('Sam');
INSERT INTO users (name) VALUES ('Jen');
INSERT INTO users (name) VALUES ('Sally');
INSERT INTO users (name) VALUES ('Tom');
INSERT INTO users (name) VALUES ('Susie');
