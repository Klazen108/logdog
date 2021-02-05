docker run --rm --net=host -it -v ${PWD}:/app python:3 bash -c 'cd /app && python logdog.py > logdog.log'

# \[(\d?\d/\d?\d/\d?\d) (\d?\d:\d?\d:\d?\d):\d?\d?\d CDT.*\]
# $2\t$1\t

# Read timed out
# 504 Gateway
# 502 Bad