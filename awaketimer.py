import datetime
import json
import time
import threading
import re

now = datetime.datetime.now()
weekday = now.strftime("%a").lower()

with open("schedule.json") as schedule:
    scheduleData = json.load(schedule)

JSONtime = scheduleData[weekday]
scheduleTime = datetime.datetime.strptime(JSONtime, "%H:%M").time()
daytime = datetime.datetime.combine(now.date(), scheduleTime)

if now < daytime:
    daytime -= datetime.timedelta(days=1)


def printAwake():
    now = datetime.datetime.now()
    diff = now - daytime
    total_seconds = int(diff.total_seconds())
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    print(f"Time awake: {hours}h {minutes}m")


def overrideListener():
    global daytime
    while True:
        userInput = input()
        # matches "5h 55m"
        match = re.match(r"(\d+)h\s*(\d+)m", userInput)
        # matches "5:55"
        if not match:
            match = re.match(r"(\d+):(\d+)", userInput)

        if match:
            h = int(match.group(1))
            m = int(match.group(2))
            now = datetime.datetime.now()
            daytime = now - datetime.timedelta(hours=h, minutes=m)
            print("Override set.")
            printAwake()
        elif userInput == "time":
            printAwake()
        else:
            print("Invalid format. Use '5h 55m' or '5:55'")


threading.Thread(target=overrideListener, daemon=True).start()

printAwake()

while True:
    now = datetime.datetime.now()
    diff = now - daytime
    completed_hours = diff.seconds // 3600 + diff.days * 24
    nextHourMark = daytime + datetime.timedelta(hours=completed_hours + 1)
    sleepTime = (nextHourMark - now).total_seconds()
    time.sleep(sleepTime)
    printAwake()
