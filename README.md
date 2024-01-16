# CookCountyPayroll

This is an exploration into the payrolls of government employees working in Cook Country, IL from 2016 to 2018. 
In the SQL script "payroll.sql," you will find:
* A summary of top earners of each fiscal year in the year 2017 (feel free to change the year)
* A view of each employee's yearly base pay
* A summary of the top 20 workers with the longest tenure
* A view of the number of jobs, offices, and employees existing in each bureau
* A function returning the jobs with the most employees
* A common table expression showing the average pay, number of jobs, and number of employees within each bureau (for bureaus with 10 or more employees who have each worked throughout all 4 quarters within a year)

Notes to viewers:
1. Since the csv file is greater than 25MB, directly download the original dataset from: https://catalog.data.gov/dataset/employee-payroll and load it into the SQL script.
2. As you look into the data, keep in mind the county fiscal quarters are: Q1: December - February Q2: March - May Q3: June - August Q4: September - November
