import sys
import urllib.request
import hashlib
import re
import codecs
import os
import json
from functools import reduce 

filterregex = None
numresults = 10
groupbythread = True

config = {}

def main():
  global filterregex
  global numresults
  global groupbythread
  global config

  if os.path.exists('config.json'):
    with open('config.json') as f:
      config = json.load(f)
  else:
    cf_out = open("sample.txt", "w")
    cf_out.write("""{
  "download_folder":"./logs",
  "skip_download":false,
  "log_files":[
    {"server":"mi2svc","file":"SystemOut.log"},
    {"server":"mi2svc2","file":"SystemOut.log"},
    {"server":"mi2svc3","file":"SystemOut.log"},
    {"server":"mi2svc4","file":"SystemOut.log"}
  ],
  "log_server_url":"http://10.127.7.79:9083/logview/downloadservlet?profile=AppServers&folder={folder}&filename={filename}",
  "default_regex":"",
  "result_limit":10,
  "download_new_files":true,
  "group_by_thread":true
}""")
    cf_out.close()

  print('Welcome to logdog (tm) 2020 Chuck Murphy')
  print('========================================')

  filterstr = config.get("default_regex","")
  numresults = config.get("result_limit",10)
  dodownload = config.get("download_new_files",True)
  groupbythread = config.get("group_by_thread",True)

  if sys.stdout.isatty():
    filterstr = input(f"(Optional) Enter a filter regular expression ({filterstr}): ")
    if filterstr.strip():
      filterregex = re.compile(filterstr.strip())
      
    numresstr = input(f"(Optional) Enter the number of results desired ({str(numresults)}): ")
    if numresstr.strip():
      try:
        numresults = int(numresstr.strip())
      except ValueError:
        print(f'invalid number "f{numresstr.strip()}", defaulting to 10')
        numresults = 10
        
    dodownloadstr = input(f"Download new files? [Y/n] ({dodownload}): ")
    if dodownloadstr.strip().upper() == "N":
      dodownload = False
        
    groupbythread = input(f"Group messages by thread? [Y/n] ({groupbythread}): ")
    if groupbythread.strip().upper() == "N":
      groupbythread = False
  
  files = []
  for logfile in config['log_files']:
    print(f"Retrieving {logfile['server']}/{logfile['file']}...",flush=True)
    files.append(getLog(logfile['server'],logfile['file'],not dodownload))

  # open files
  streamsavers = []
  for filename in files:
    print(f'Loading {filename}',flush=True)
    streamsavers.append(loadStreamsaver(filename))

  # get first entry TODO: correct?
  for streamsaver in [x for x in streamsavers if x.ready]:
    print(f'Preparing {streamsaver.filename}...',flush=True)
    getLogEntry(streamsaver)

  # read from files
  logmap = {}
  for streamsaver in [x for x in streamsavers if x.ready]:
    print(f'Consuming {streamsaver.filename}...',flush=True)
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

  print('Sorting...',flush=True)
  sortedlogs = list(logmap.values())
  sortedlogs.sort(key=lambda logcnt: logcnt.count, reverse=True)
  
  print('\nResults:\n',flush=True)
  if len(sortedlogs)==0 and filterregex:
    print(f'no matches for: {filterregex}',flush=True)
  if len(sortedlogs)==0 and not filterregex:
    print(f'no log entries.',flush=True)
  for i in range(0,numresults):
    if i >= len(sortedlogs):
      break
    print(f'(logdog)>{sortedlogs[i].count} times:')
    for line in sortedlogs[i].logentry.lines:
      print(line.replace('\r\n',''))
    print('\n',flush=True)
  
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
# The line is considered part of the same log if the thread id is the same
# and the timestamp has increased by at most one-thousandth of a second.
def isSameEntry(logline,currentThreadId,currentTimestamp):
  global groupbythread
  
  parsedline = None
  try:
    parsedline = parseLogline(logline)
  except ValueError:
    return currentTimestamp

  if not groupbythread:
    return False
  
  #get numeric value of this line
  ts = parsedline.timestamp
  tsnm = tstimeregex.match(ts)
  if not tsnm:
    raise ValueError("Invalid timestamp: "+ts)
  tsnumeric = int(tsnm[1]+tsnm[2]+tsnm[3]+tsnm[4])
  
  #get numeric value of current line
  tsnmc = tstimeregex.match(currentTimestamp)
  if not tsnmc:
    raise ValueError("Invalid timestamp: "+currentTimestamp)
  tscnumeric = int(tsnmc[1]+tsnmc[2]+tsnmc[3]+tsnmc[4])

  # isStackTrace = 'SystemErr     R 	at' in logline
  # isStackTrace = isStackTrace or 'SystemErr     R Caused by' in logline

  sameTime = tsnumeric <= tscnumeric+1
  sameThread = parsedline.threadid == currentThreadId
  # if isStackTrace or (sameTime and sameThread):
  if sameTime and sameThread:
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
  i = 0
  while True:
    line = streamsaver.file.readline()
    i=i+1
    if not line:
      streamsaver.ready = False
      print('No log content detected.')
      return False
    if loglineregex.match(line):
      streamsaver.lastline = line
      streamsaver.timestamp = parseLogline(line).timestamp
      streamsaver.ready = True
      print('Ready at line '+str(i)+".")
      return True

loglineregex = re.compile('^\[(\d[^\]]+)\]\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*)$')
def parseLogline(logline):
  match = loglineregex.match(logline)
  if match:
    return ParsedLine(match.groups())
  else:
    raise ValueError('This line was of an unexpected format:\n'+logline)


def getLog(folder,filename,skipdownload):
  if not os.path.exists(config['download_folder']):
      os.makedirs(config['download_folder'])

  if not skipdownload:
    # blmotqaecowas01 wasn't working from container, so replaced with ip
    url = config['log_server_url'].format(folder=folder, filename=filename)
    filename = os.path.join(config['download_folder'],f'{folder}-{filename}')
    urllib.request.urlretrieve(url, filename)
  return filename

if __name__ == "__main__":
  # execute only if run as a script
  main()