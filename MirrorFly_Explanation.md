# MirrorFly Authentication Script: Explained Simply

This document explains the Python script `MirrorFly_bck.py` in very simple terms, using an analogy of a **Security Guard** at a VIP Club.

---

## 1. The Big Picture
This script acts as a **Security Guard** for your Chat Server. Whenever someone tries to log in, the Chat Server (The Manager) asks this guard: *"Is this person allowed to enter?"* 

The guard then checks their ID, sometimes calls the "Main Office" (an API), and gives a final "Yes" or "No" answer.

---

## 2. The Guard’s Tools (Imports)
At the very top of the script, the `import` lines are the tools the guard uses:
*   **`sys` & `struct`**: His walkie-talkie to hear the Manager and reply.
*   **`requests`**: His phone to call the Main Office and verify guests.
*   **`json`**: A special notebook format for writing Guest Info.
*   **`datetime` & `time`**: His watch to know the exact time.

---

## 3. The Core Functions

### `log(string)` — The Daily Diary
The guard keeps a secret logbook at `/opt/ejabberd/sso-auth.log`. Every time a guest arrives or something goes wrong, he writes down the time and the details. This helps the manager see what happened during the night.

### `read()` — The Listening Ear
This is the guard's main job. He waits by the door for a message from the Manager.
1.  **Measuring the Message**: He reads the first two characters to know how long the name and password will be.
2.  **Checking the Command**: He looks at the first word to see what to do:
    *   `auth`: A guest wants to log in.
    *   `isuser`: Is this person even a member?
    *   `removeuser`: Kick this person out of the club!

### `write(result)` — The Secret Signal
The guard doesn't speak. He uses a special light signal:
*   **GREEN LIGHT** (`\x00\x02\x00\x01`): "Yes, let them in!"
*   **RED LIGHT** (`\x00\x02\x00\x00`): "No, keep the door shut!"

---

## 4. The Guest Check (`auth` logic)
This is the heart of the script. When someone tries to log in:

1.  **Skip the Line**: 
    *   If the name is `"wrong"`, the guard says "No!" immediately.
    *   If the password is `"allow"`, the guard says "Welcome!" without checking anything else.
2.  **The Phone Call**: 
    *   For everyone else, the guard takes their `username` and `password`.
    *   He notes the `timestamp` (the exact second they arrived).
    *   He uses his phone (`requests.post`) to call the **Main Office** (the URL provided).
3.  **The Office Decision**: 
    *   If the Office says "Okay" (Codes 200/201/202) and the status in his notebook is 200, he lets them in.
    *   If the office says "No" or if the phone line cuts, he gives a Red Light.

---

## 5. Important Python Terms
*   **`split(':')`**: Imagine a piece of string like `"A:B:C"`. This command cuts the string at every `:` to give the pieces `A`, `B`, and `C` separately.
*   **`try...except`**: This is for "Safety First." If something breaks (like the phone line goes dead), the script doesn't crash; it just writes the error in the logbook and keeps working.
*   **`json.dumps`**: This turns a list of info into a special text format that websites understand.
*   **`time.time()`**: This gives the number of seconds since the year 1970—standard "Computer Time."
