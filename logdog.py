import sys
import urllib.request
import hashlib
import re
import codecs
from functools import reduce 

filterregex = None
numresults = 10
def main():
  global filterregex
  global numresults
  print('Welcome to logdog (tm) 2020 Chuck Murphy')
  print('========================================')

  filterstr = input("(Optional) Enter a filter regular expression: ")
  if filterstr.strip():
    filterregex = re.compile(filterstr.strip())
    
  numresstr = input("(Optional) Enter the number of results desired (default 10): ")
  if numresstr.strip():
    try:
      numresults = int(numresstr.strip())
    except ValueError:
      print(f'invalid number "f{numresstr.strip()}", defaulting to 10')
      numresults = 10
      
  skipdownload = False
  dodownloadstr = input("Download new files? [Y/n]: ")
  if dodownloadstr.strip().upper() == "N":
    skipdownload = True
  
  files = []
  print(f'Retrieving inMotion1-Linux...')
  files.append(getLog('inMotion1-Linux','SystemOut.log',skipdownload))
  files.append(getLog('inMotion1-Linux','SystemErr.log',skipdownload))
  print(f'Retrieving inMotion2-Linux...')
  files.append(getLog('inMotion2-Linux','SystemOut.log',skipdownload))
  files.append(getLog('inMotion2-Linux','SystemErr.log',skipdownload))
  print(f'Retrieving inMotion3-Linux...')
  files.append(getLog('inMotion3-Linux','SystemOut.log',skipdownload))
  files.append(getLog('inMotion3-Linux','SystemErr.log',skipdownload))
  print(f'Retrieving inMotion4-Linux...')
  files.append(getLog('inMotion4-Linux','SystemOut.log',skipdownload))
  files.append(getLog('inMotion4-Linux','SystemErr.log',skipdownload))

  #combinedfilename = 'combined-inMotion1-Linux-SystemOut.log'
  #with open(combinedfilename,'w') as outstream:

  # open files
  streamsavers = []
  for filename in files:
    print(f'Loading {filename}')
    streamsavers.append(loadStreamsaver(filename))

  # get first entry TODO: correct?
  for streamsaver in streamsavers:
    print(f'Preparing {streamsaver.filename}...')
    getLogEntry(streamsaver)

  # read from files
  logmap = {}
  for streamsaver in [x for x in streamsavers if x.ready]:
    print(f'Consuming {streamsaver.filename}...')
    while streamsaver.ready:
      getLogEntry(streamsaver)

      # filter out non-matching entries
      if filterregex and not linesContain(streamsaver.lastlog.lines,filterregex):
        continue
      
      # add one to number of times seen
      logcnt = logmap.get(streamsaver.lastlog.hash,None)
      if not logcnt:
        logcnt = LogCount()
        logcnt.logentry = streamsaver.lastlog
        logcnt.count = 1
      else:
        logcnt.count = logcnt.count + 1
      logmap[streamsaver.lastlog.hash] = logcnt

  print('Sorting...')
  sortedlogs = list(logmap.values())
  sortedlogs.sort(key=lambda logcnt: logcnt.count, reverse=True)
  
  print('\nResults:\n')
  if len(sortedlogs)==0 and filterregex:
    print(f'no matches for: {filterregex}')
  if len(sortedlogs)==0 and not filterregex:
    print(f'no log entries.')
  for i in range(0,numresults):
    if i >= len(sortedlogs):
      break
    print(f'(logdog)>{sortedlogs[i].count} times:')
    for line in sortedlogs[i].logentry.lines:
      print(line.replace('\r\n',''))
    print('\n')
  
  # biggestlog = reduce(reduceToBiggestLog, logmap.values(), LogCount())
  # print('Biggest log:')
  # print(f'{biggestlog.count} times')
  # print(biggestlog.logentry.lines)

class LogEntry(object):
  lines = []
  timestamp = ""
  hashfirstline = ""

class Streamsaver(object):
  file = False
  filename = ""
  lastlog = LogEntry()
  lastline = ""
  ready = False

class LogCount(object):
  logentry = None
  count = 0

class ParsedLine(object):
  timestamp = ""
  threadid = ""
  stream = ""
  typeKey = ""
  message = ""

  def __init__(self, values):
    self.timestamp = values[0]
    self.threadid = values[1]
    self.stream = values[2]
    self.typeKey = values[3]
    self.message = values[4]

def linesContain(lines,regex):
  msg = reduce(lambda acc,cur: acc+cur, lines, "")
  return regex.search(msg)

def reduceToBiggestLog(biggest,current):
  if current.count > biggest.count:
    return current
  else:
    return biggest

# Creates a Streamsaver object from a filename, and gets it ready for work
def loadStreamsaver(filename):
  streamsaver = Streamsaver()
  curfile = codecs.open(filename,'r',encoding='utf-8',errors='ignore')
  streamsaver.file = curfile
  streamsaver.filename = filename
  getFileReady(streamsaver)
  return streamsaver

tstimeregex = re.compile('^\d?\d\/\d?\d\/\d?\d\s+(\d?\d):(\d?\d):(\d?\d):(\d?\d?\d)\s+.*$')
# Returns the new "current timestamp" if the log entry is considered part of the
# current log entry, which is truthy. Otherwise returns false.
def isSameEntry(logline,currentThreadId,currentTimestamp):
  islogline = loglineregex.match(logline)
  if not islogline:
    return currentTimestamp

  #get numeric value of this line
  ts = parseLogline(logline).timestamp
  tsnm = tstimeregex.match(ts)
  if not tsnm:
    raise ValueError("Invalid timestamp: "+ts)
  tsnumeric = int(tsnm[1]+tsnm[2]+tsnm[3]+tsnm[4])
  
  #get numeric value of current line
  tsnmc = tstimeregex.match(currentTimestamp)
  if not tsnmc:
    raise ValueError("Invalid timestamp: "+currentTimestamp)
  tscnumeric = int(tsnmc[1]+tsnmc[2]+tsnmc[3]+tsnmc[4])

  # print(tsnumeric)
  # print(tscnumeric)
  # sys.exit(1)

  threadid = islogline[1]

  isStackTrace = 'SystemErr     R 	at' in logline
  sameTime = tsnumeric <= tscnumeric+1
  sameThread = threadid == currentThreadId
  # same log entry if both...
  # the timestamp is same or greater by one thousandth of a second
  # the thread id of the new line is the same as the current line
  if isStackTrace or (sameTime and sameThread):
    return ts
  else:
    return False

def getLogEntry(streamsaver):
  # assume current lastline is the start of a new log entry
  streamsaver.lastlog = LogEntry()
  streamsaver.lastlog.lines = []
  streamsaver.lastlog.lines.append(streamsaver.lastline)
  parsedline = parseLogline(streamsaver.lastline)
  streamsaver.lastlog.hash = hashlib.md5(parsedline.message.encode()).hexdigest()
  streamsaver.lastlog.timestamp = parsedline.timestamp
  currentThreadId = parsedline.threadid

  #read the next line to see if it's part of the same entry
  try:
    streamsaver.lastline = streamsaver.file.readline()
    currentTimestamp = streamsaver.lastlog.timestamp
    currentTimestamp = isSameEntry(streamsaver.lastline,currentThreadId,currentTimestamp)
    while streamsaver.lastline and currentTimestamp:
      streamsaver.lastlog.lines.append(streamsaver.lastline)
      streamsaver.lastline = streamsaver.file.readline() # will be falsy when EOF
      currentTimestamp = isSameEntry(streamsaver.lastline,currentThreadId,currentTimestamp)
  except UnicodeDecodeError:
    print(f'UnicodeDecodeError after line: {streamsaver.lastline}')
    getToSafety(streamsaver)

  streamsaver.ready = streamsaver.lastline

def getToSafety(streamsaver):
  i = 100
  while streamsaver.lastline and i > 0:
    i = i - 1
    try:
      streamsaver.lastline = streamsaver.file.readline()
      # continue until the next entry start
      if loglineregex.match(streamsaver.lastline):
        print('UnicodeDecodeError Recovered.')
        return
    except UnicodeDecodeError:
      # we're already up the creek, just keep trying to get ashore
      pass
  if i == 0:
    raise ValueError('Unable to recover after 100 lines!')

# Gets a log file ready by positioning the stream cursor at the first actual log line.
# Returns true if there's log data to read, false if not.
def getFileReady(streamsaver):
  while True:
    line = streamsaver.file.readline()
    if not line:
      streamsaver.ready = False
      return False
    if loglineregex.match(line):
      streamsaver.lastline = line
      streamsaver.timestamp = parseLogline(line).timestamp
      streamsaver.ready = True
      return True

loglineregex = re.compile('^\[(\d[^\]]+)\]\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*)$')
def parseLogline(logline):
  match = loglineregex.match(logline)
  if match:
    return ParsedLine(match.groups())
  else:
    raise ValueError('This line was of an unexpected format:\n'+logline)


def getLog(folder,filename,skipdownload):
  if not skipdownload:
    url = f'http://blmotqaecowas01:9083/logview/downloadservlet?profile=AppServers&folder={folder}&filename={filename}'
    urllib.request.urlretrieve(url, f'{folder}-{filename}')
  return f'{folder}-{filename}'

if __name__ == "__main__":
  # execute only if run as a script
  main()