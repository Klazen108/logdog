**Logdog** Is a utility by Chuck Murphy for quickly retrieving log files from the Motion servers and sorting the results, to see the most common messages being printed to the console.

- 2020-07-16 DP072885

# How to Run

## Docker

We recommend using Docker to run logdog, to avoid having to set up Python.

If you have Docker, you can run logdog quickly with the following command:

```ps1
docker run --rm --net=host -it -v ${PWD}:/app python:3 bash -c 'cd /app && python logdog.py'
```

(a `.ps1` script is included to make this easy - just execute `./run`)

Note that if you receive an error mounting the directory on Windows, it's probably because you haven't given Docker Desktop permission to mount the drive. [Read more here](https://rominirani.com/docker-on-windows-mounting-host-directories-d96f3f056a2c?gi=9a1b7384f4bd)

## Linux / Windows

Logdog was written against [Python 3.7](https://www.python.org/downloads/release/python-370/). Once installed, you can run logdog with the following command:

```ps1
python logdog.py
```

## Headless

If you pipe the output of logdog to a file (stdout is not a tty console) then logdog will skip the initial prompt for settings. This is very useful for automation purposes. The above commands should be modified as follows:

```ps1
docker run --rm --net=host -it -v ${PWD}:/app python:3 bash -c 'cd /app && python logdog.py > output.txt'
python logdog.py > output.txt
```

# Configuration

Logdog settings are available in `config.json`. Commonly changed settings are prompted at runtime, but if run in headless mode, then logdog will suppress the prompt. If the file is deleted, logdog will create a new one with default values.

## Example Config File

```json
{
    "download_folder":"./logs",
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
}
```

## Setting Definitions

* download_folder: Where log files are saved to
* log_files: list of log files to be downloaded
    * server: the "folder" (aka server) to view log files under
    * file: the log file to grab
* log_server_url: URL to the log server. {folder} marks where the server value is inserted, and {filename} where the file is.
* default_regex: regular expression to use to filter log lines. Blank by default.
* result_limit: number of results to print after grouping and sorting the logs. printed in order of occurrences, descending. Default 10.
* download_new_files: whether or not to download files. Set to false if you want to rerun logdog on files you've already downloaded. Default true.
* group_by_thread: if true, attempts to group successive log lines that were printed by the same print command, or ones closely related (must have the same thread ID and be within one millisecond). Default true.