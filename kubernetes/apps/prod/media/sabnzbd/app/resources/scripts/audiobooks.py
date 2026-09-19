# https://gist.github.com/vicegold/a786155693e39520cd84cd352e65877a
import importlib
import subprocess
import sys
import requests
import shutil
import re
from pathlib import Path
from mutagen import File
from unidecode import unidecode

AUDIOBOOK_FOLDER = "" # "/audiobooks" - Path where you mounted your audiobooks in the SABnzbd docker container
ABS_URL = "" # "http://localhost:13378"
ABS_LIBRARY = None # "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
ABS_BEARER = None # "eyHUAFHW…"
PUSHOVER_TOKEN = None # Pushover app token "xxxxxxxxxxxxxxxxxxxxx"
PUSHOVER_USER = None # Pushover user key "xxxxxxxxxxxxxxxxxxxxx"

# Common audiobook extensions to check for
AUDIO_EXTENSIONS = ('.mp3', '.m4a', '.m4b', '.aac', '.ogg', '.opus', '.flac')

try:
    (scriptname, directory, orgnzbname, jobname, reportnumber, category, group, postprocstatus, url) = sys.argv
except:
    scriptname = "/config/scripts/audiobooks.py"
    directory = "/Downloads/complete/Examplebook (1988)"
    orgnzbname = "Examplebook (1988)"
    jobname = "Examplebook (1988){{rel.aud}}"
    reportnumber = "null"
    category = "audiobooks"
    group = "alt"
    postprocstatus = "0"
    url = "null"

def refresh_abs_library():
    if not ABS_LIBRARY or not ABS_URL or not ABS_BEARER:
        return
    url = f"{ABS_URL}/api/libraries/{ABS_LIBRARY}/scan"
    headers = {
        "Authorization": f"Bearer {ABS_BEARER}"
    }
    response = requests.post(url, headers=headers)
    return response.status_code == 200

def send_pushover_notification(message, cover=None):
    if not PUSHOVER_TOKEN or not PUSHOVER_USER:
        return
    url = "https://api.pushover.net/1/messages.json"

    files = None

    payload = {
        "token": PUSHOVER_TOKEN,
        "user": PUSHOVER_USER,
        "message": message,
    }

    if cover:
        extension = Path(cover).suffix.lower()
        content_type = "image/jpeg"  # Default content type

        if extension == '.png':
            content_type = "image/png"
        elif extension in ('.jpg', '.jpeg'):
            content_type = "image/jpeg"
        elif extension == '.gif':
            content_type = "image/gif"

        filename = Path(cover).name
        files = {
            "attachment": (filename, open(cover, "rb"), content_type)
        }

    response = requests.post(url, data=payload, files=files)
    return response.status_code == 200

def sanitize_filename(filename):
    invalid_chars = r'[<>:"\\\|?*\x00-\x1F]'
    replace = re.sub(invalid_chars, '', filename)
    special_char_map = {ord('ä'):'ae', ord('Ä'):'Ae', ord('ü'):'ue', ord('Ü'):'Ue', ord('ö'):'oe', ord('Ö'):'Oe', ord('ß'):'ss'}
    return unidecode(replace.translate(special_char_map))

def use_optional_library():
    package = 'mutagen'
    try:
        optional_lib = importlib.import_module('mutagen')
        print(optional_lib)
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])
        try:
            pkg = importlib.import_module(package)
            print(f'{package} ({pkg.__version__}) is installed')
        except ImportError:
            message = f"Failed to import {package}"
            print(message)
            send_pushover_notification(message)

use_optional_library()

def process_files(directory_path):

    data = {
        "title": None,
        "author": None,
        "series": None,
        "series_part": None,
        "year": None,
        "narrators": []
    }

    path = Path(directory_path)

    try:
        audio_file = next(f for f in path.glob('**/*.*') if f.suffix.lower() in AUDIO_EXTENSIONS)
        try:
            audio = File(str(audio_file))
            if audio is not None:
                print(f"\nProcessing: {audio_file.name}")
                if hasattr(audio, 'tags') and audio.tags:
                    for key in audio.tags.keys():
                        if "TALB" in audio.tags.keys():
                            data["title"] = audio.tags["TALB"][0]
                        elif "TIT2" in audio.tags.keys():
                            data["title"] = audio.tags["TIT2"][0]
                        elif "©nam" in audio.tags.keys():
                            data["title"] = audio.tags["©nam"][0]
                        elif "©alb" in audio.tags.keys():
                            data["title"] = audio.tags["©alb"][0]

                        if type(data.get("title")) == list:
                            data["title"] = data.get("title")[0]

                        if ';' in data.get("title"):
                            data["title"] = data.get("title").split(';')[0]

                        if "TPE1" in audio.tags.keys():
                            data["author"] = audio.tags["TPE1"][0]
                        elif "TPE2" in audio.tags.keys():
                            data["author"] = audio.tags["TPE2"][0]
                        elif "©ART" in audio.tags.keys():
                            data["author"] = audio.tags["©ART"][0]
                        elif "aART" in audio.tags.keys():
                            data["author"] = audio.tags["aART"][0]

                        if type(data.get("author")) == list:
                            data["author"] = data.get("author")[0]

                        if ';' in data.get("author"):
                            data["author"] = data.get("author").split(';')[0]

                        if data.get("year") == None:
                            if "TDRC" in audio.tags.keys():
                                data["year"] = audio.tags["TDRC"][0]
                            if "©day" in audio.tags.keys():
                                data["year"] = int(audio.tags["©day"][0].split('-')[0])

                        if len(data.get("narrators")) == 0:
                            narrators = []
                            if "TCOM" in audio.tags.keys():
                                narrators = list(audio.tags["TCOM"])
                            elif "TXXX:NARRATEDBY" in audio.tags.keys():
                                narrators = list(audio.tags["TXXX:NARRATEDBY"])
                            elif "NARRATOR" in audio.tags.keys():
                                narrators = list(audio.tags["NARRATOR"])
                            elif "©wrt" in audio.tags.keys():
                                narrators = list(audio.tags["©wrt"])
                            elif "©nrt" in audio.tags.keys():
                                narrators = list(audio.tags["©nrt"])

                            if len(narrators) > 0:
                                for narrator in narrators:
                                    if ';' in narrator:
                                        narrators = narrator.split(';')
                                        for n in narrators:
                                            if n not in data.get("narrators"):
                                                data["narrators"].append(n.strip())
                                    else:
                                        if narrator not in data.get("narrators"):
                                            data["narrators"].append(narrator)

                else:
                    print(f"Could not read audio file or no tags found: {audio_file}")
        except Exception as e:
            print(f"Error processing {audio_file}: {str(e)}")
    except StopIteration:
        print("No audio files found in directory")
    except Exception as e:
        print(f"Error: {str(e)}")

    return data

data = process_files(directory)

if data is None:
    error = "Error processing audiobook files"
    print(error)
    send_pushover_notification(error)
    sys.exit(1)

folder = f"{AUDIOBOOK_FOLDER}/{data.get('author')}/"

if data.get('series'):
    folder += f"{data.get('series')}/"

folder += f"{data.get('year')} - "

if data.get('series_part'):
    folder += f"Book {data.get('series_part')} - "

folder += f"{data.get('title')}"

if data.get('narrators'):
    narrators_str = ", ".join(data.get('narrators'))
    folder += f" {{{narrators_str}}}"

cover = None

try:
    folder = sanitize_filename(folder)

    Path(folder).mkdir(parents=True, exist_ok=True)

    path = Path(directory)
    for file in path.glob('**/*.*'):
        if file.suffix.lower() in AUDIO_EXTENSIONS:
            destination = Path(folder) / file.name
            print(f"Copy {file.name} to {destination}")
            shutil.copy(str(file), str(destination))
        if file.suffix.lower() in (".jpg", ".jpeg", ".png", ".gif"):
            destination = Path(folder) / f"cover{file.suffix.lower()}"
            print(f"Copy & rename cover {file.name} to {destination}")
            shutil.copy(str(file), str(destination))
            cover = str(destination)
        if file.name.lower() == "metadata.json":
            destination = Path(folder) / "metadata.json"
            print(f"Copy {file.name} to {destination}")
            shutil.copy(str(file), str(destination))

except Exception as e:
    error = f"Error copying audiobook files: {str(e)}"
    print(error)
    send_pushover_notification(error)
    sys.exit(1)

try:
    if ABS_LIBRARY and ABS_URL and ABS_BEARER:
        refresh_abs_library()
except Exception as e:
    error = f"Error refreshing ABS library: {str(e)}"
    print(error)
    send_pushover_notification(error)
    sys.exit(1)

success = f"New audiobook: {data.get('title')} by {data.get('author')}"
send_pushover_notification(success, cover if cover else None)

try:
    shutil.rmtree(directory)
    print(f"Deleted folder: {directory}")
except Exception as e:
    print(f"Error deleting folder {directory}: {str(e)}")

print(success)
sys.exit(0)
