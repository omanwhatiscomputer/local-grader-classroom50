This script is written for Linux/MacOS

This repository hosts the bash script to locally autograde classroom50.

To create the scoring.json file copy the json entry for the assignment in "https://github.com/CSCI4300-Web-Programming/classroom50/blob/main/tester/assignments.json"

Exmaple scoring files have been included


```
TEMPLATE_DIR -> the directory of the template
SUBMISSIONS_DIR -> the directory containg all student submissions
SCORING_FILE -> path to the scoring.json file
OUTPUT_CSV -> name of the output file
CLASS_TIME -> AM or PM, picks roster/am-roster.csv or roster/pm-roster.csv
ROSTER_DIR -> the directory containing the roster csv files
KEEP_IN_TEMPLATE -> files/folders kept from the template for every student (the student's copies are ignored)
```

To run the script
```
chmod +x grade.sh
bash grade.sh
```

# Where to grab the template?
From CSCI4300 Web Programming group in github 
