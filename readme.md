This script is written for Linux/MacOS

This repository hosts the bash script to grade classroom 50 workflow locally.

To create the scoring.json file copy the json entry for the assignment in "https://github.com/CSCI4300-Web-Programming/classroom50/blob/main/tester/assignments.json"

```
TEMPLATE_DIR -> the directory of the template
SUBMISSIONS_DIR -> the directory containg all student submissions
SCORING_FILE -> path to the scoring.json file
OUTPUT_CSV -> name of the output file
```

To run the script
```
chmod +x grade.sh
bash grade.sh
```
