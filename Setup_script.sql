-- Creating the database 
DROP database if exists agriculture;
CREATE DATABASE agriculture;

-- Using Database
USE agriculture;

-- Creating the table
DROP TABLE IF EXISTS dataset;
CREATE TABLE dataset(
	arrival_date DATE,
    commodity  VARCHAR(20),
    state VARCHAR(20),
    district VARCHAR(20),
    market VARCHAR(20),
    variety VARCHAR(20),
    grade VARCHAR(20),
    min_price INT,
    max_price INT,
    modal_price INT,
    quintal FLOAT
)
