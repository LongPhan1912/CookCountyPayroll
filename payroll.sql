DROP TABLE IF EXISTS payroll;

CREATE TABLE payroll (
    fiscal_year INT NOT NULL,
    fiscal_quarter INT NOT NULL,
    fiscal_period VARCHAR(10) NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    middle_init VARCHAR(20),
    bureau VARCHAR(50) NOT NULL,
    office INT,
    office_name VARCHAR(50),
    job_code INT NOT NULL,
    job_title VARCHAR(50) NOT NULL,
    base_pay NUMERIC(10,1),
    position_id INT NOT NULL,
    employee_id VARCHAR(50) NOT NULL,
    original_hire_date DATE NOT NULL
);

-- Load the csv data into the table
COPY payroll
FROM '/Users/longphan/Downloads/Employee_Payroll.csv'
DELIMITER ','
CSV HEADER;

-- Clean the data by setting base_pay to 0 if it is null
UPDATE payroll
SET base_pay = 0
WHERE base_pay IS NULL;

-- Set all names to uppercase
CREATE OR REPLACE PROCEDURE capitalize_all_names()
AS $$

BEGIN
    UPDATE payroll
    SET first_name = UPPER(first_name)
    WHERE first_name != UPPER(first_name);

    UPDATE payroll
    SET last_name = UPPER(last_name)
    WHERE last_name != UPPER(last_name);

    UPDATE payroll
    SET middle_init = UPPER(middle_init)
    WHERE middle_init != UPPER(middle_init);

    UPDATE payroll
    SET bureau = UPPER(bureau)
    WHERE bureau != UPPER(bureau);
END;
$$ LANGUAGE plpgsql;
-- CALL capitalize_all_names();


-- Sanity checking for original_hire_date
SELECT first_name, last_name, original_hire_date from payroll WHERE EXTRACT(YEAR from original_hire_date) > 2018 LIMIT 25;


-- Find the top 10 earners of 2017
SELECT full_name, fiscal_year, SUM(base_pay) FROM (
    SELECT 
        DISTINCT(CONCAT(first_name, ' ', COALESCE(middle_init || ' ', ''), last_name)) AS full_name,
        fiscal_year,
        base_pay
    FROM payroll
)
WHERE fiscal_year = 2017
GROUP BY full_name, fiscal_year
ORDER BY SUM(base_pay) DESC
LIMIT 10;


-- Get the yearly base pay for all employees ordered by their full name (ascending)
CREATE OR REPLACE VIEW yearly_base_pay AS
SELECT 
    full_name, 
    SUM(base_pay) FILTER (WHERE fiscal_year = 2016) AS "2016",
    SUM(base_pay) FILTER (WHERE fiscal_year = 2017) AS "2017",
    SUM(base_pay) FILTER (WHERE fiscal_year = 2018) AS "2018"
FROM (
    SELECT 
        DISTINCT(CONCAT(first_name, ' ', COALESCE(middle_init || ' ', ''), last_name)) AS full_name,
        fiscal_year,
        base_pay
    FROM payroll
)
GROUP BY full_name
ORDER BY full_name;


-- Create a lookup table for fiscal period end dates (so we can calculate the employee's years of service)
DROP TABLE IF EXISTS fiscal_period_lookup;

CREATE TABLE fiscal_period_lookup (
    fiscal_period VARCHAR(10) NOT NULL,
    period_end_date DATE,
    fiscal_year INT NOT NULL,
    fiscal_quarter INT NOT NULL
);


-- Create a function to state the corresponding end date for a given fiscal period
-- NOTE: The county fiscal quarters are: Q1: December - February Q2: March - May Q3: June - August Q4: September - November
CREATE OR REPLACE FUNCTION get_fiscal_period_end_date(fiscal_year INT, fiscal_quarter INT)
    RETURNS DATE AS $$

DECLARE m INT; d INT;

BEGIN
    IF fiscal_quarter = 1 THEN
        IF fiscal_year % 4 = 0 THEN
            m = 2; d = 29;
        ELSE
            m = 2; d = 28;
        END IF;
    ELSIF fiscal_quarter = 2 THEN
        m = 5; d = 31;
    ELSIF fiscal_quarter = 3 THEN
        m = 8; d = 31;
    ELSE
        m = 11; d = 30;
    END IF;
    RETURN make_date(fiscal_year, m, d);
END;
$$ LANGUAGE plpgsql;

-- Insert into the table the unique fiscal periods along with their respective end dates, years, and quarters
INSERT INTO 
    fiscal_period_lookup
SELECT 
    fiscal_period, get_fiscal_period_end_date(fiscal_year, fiscal_quarter) AS period_end_date, fiscal_year, fiscal_quarter
FROM (
    SELECT DISTINCT fiscal_period, fiscal_year, fiscal_quarter
    FROM payroll 
    ORDER BY fiscal_period
);


-- Find the top 20 employees with the longest tenure
-- Fun fact: The longest tenure is held by Stanley Gizewski, who worked for the county for 59 years and 10 months as of 2018-05-31.
-- He recently passed away at 86 on 2023-11-28 and served 66 years in total for the Cook County Department of Public Health. 
-- Link: https://www.dignitymemorial.com/obituaries/orland-park-il/stanley-gizewski-11561811

WITH cte1 AS (
    SELECT 
        DISTINCT(CONCAT(first_name, ' ', COALESCE(middle_init || ' ', ''), last_name)) AS full_name,
        original_hire_date,
        fiscal_period
    FROM payroll
), cte2 AS (
    SELECT full_name, original_hire_date, MAX(fiscal_period) AS latest_fiscal_period
    FROM cte1
    GROUP BY full_name, original_hire_date
)
SELECT 
    cte2.full_name, 
    cte2.original_hire_date, 
    f.period_end_date AS latest_hire_date, 
    AGE(f.period_end_date,cte2.original_hire_date) AS length_of_employement
FROM cte2
JOIN fiscal_period_lookup AS f
ON cte2.latest_fiscal_period = f.fiscal_period
ORDER BY length_of_employement DESC
LIMIT 20;


-- Get the number of jobs and employees in each bureau
CREATE OR REPLACE VIEW bureau_summary AS
SELECT 
    DISTINCT bureau, 
    COUNT(DISTINCT office) AS number_of_offices,
    COUNT(DISTINCT job_code) AS number_of_jobs,
    COUNT(DISTINCT employee_id) AS number_of_employees
FROM payroll 
GROUP BY bureau 
ORDER BY number_of_offices DESC;


-- Find the jobs with the most employees
-- Returns a table with the job title, office name, number of employees, and total base pay
CREATE OR REPLACE FUNCTION jobs_by_number_of_employees(y INT) 
    RETURNS TABLE(job VARCHAR, office VARCHAR, num_employees BIGINT, total_pay NUMERIC) AS $$

BEGIN
    RETURN QUERY SELECT 
        DISTINCT job_title, office_name,
        COUNT(DISTINCT employee_id) AS number_of_employees,
        SUM(base_pay) AS total_base_pay
    FROM payroll 
    WHERE fiscal_year = y
    GROUP BY fiscal_year, job_title, office_name
    ORDER BY number_of_employees DESC;
END;
$$ LANGUAGE plpgsql;


-- In the year 2016, view the highest salaries by the following business logic (please comment/uncomment the chunks of code as appropriate)...
WITH detailed_employee_records AS (
    SELECT 
        DISTINCT (CONCAT(first_name, ' ', COALESCE(middle_init || ' ', ''), last_name)) AS full_name,
        employee_id,
        job_code,
        fiscal_year,
        fiscal_quarter,
        base_pay
    FROM payroll
), summarized_employee_records AS (
    SELECT 
        full_name,
        employee_id,
        job_code,
        fiscal_year,
        COUNT(fiscal_quarter) AS quarters_worked,
        SUM(base_pay) AS total_pay
    FROM detailed_employee_records
    GROUP BY full_name, employee_id, job_code, fiscal_year
), workers_by_office AS (
    SELECT 
        DISTINCT bureau, office_name, job_title, job_code, employee_id
    FROM payroll
    -- Make sure to filter the fiscal year because an office may change its respective bureau over time
    WHERE fiscal_year = 2016
)
-- 1/ Bureaus with 10 or more employees where each employee has worked for all 4 quarters
SELECT 
    w.bureau,
    COUNT(DISTINCT w.job_code) AS number_of_jobs,
    COUNT(DISTINCT w.employee_id) AS number_of_employees,
    ROUND(AVG(s.total_pay)) AS average_pay
FROM summarized_employee_records AS s
JOIN workers_by_office AS w
ON s.employee_id = w.employee_id AND s.job_code = w.job_code
WHERE s.quarters_worked = 4 AND s.fiscal_year = 2016
GROUP BY w.bureau
HAVING COUNT(DISTINCT w.employee_id) >= 10
ORDER BY AVG(s.total_pay) DESC;


-- 2/ Offices with 10 or more employees where each employee has worked for all 4 quarters
-- SELECT 
--     w.office_name,
--     COUNT(DISTINCT w.job_code) AS number_of_jobs,
--     COUNT(DISTINCT w.employee_id) AS number_of_employees,
--     ROUND(AVG(s.total_pay)) AS average_pay
-- FROM summarized_employee_records AS s
-- JOIN workers_by_office AS w
-- ON s.employee_id = w.employee_id AND s.job_code = w.job_code
-- WHERE s.quarters_worked = 4 AND s.fiscal_year = 2016
-- GROUP BY w.office_name
-- HAVING COUNT(DISTINCT w.employee_id) >= 10
-- ORDER BY AVG(s.total_pay) DESC;


-- 3/ Individual jobs with 10 or more employees working in each job and each employee has worked for all 4 quarters
-- SELECT 
--     w.bureau,
--     w.office_name, 
--     w.job_title,
--     COUNT(w.employee_id) AS number_of_employees,
--     ROUND(AVG(s.total_pay)) AS average_pay
-- FROM summarized_employee_records AS s
-- JOIN workers_by_office AS w
-- ON s.employee_id = w.employee_id AND s.job_code = w.job_code
-- WHERE s.quarters_worked = 4 AND s.fiscal_year = 2016
-- GROUP BY w.bureau, w.office_name, w.job_title
-- HAVING COUNT(DISTINCT w.employee_id) >= 10
-- ORDER BY AVG(s.total_pay) DESC;

