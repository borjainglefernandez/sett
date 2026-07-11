#!/usr/bin/env python3
"""Generate Saiyan-style exercise icons via the Gemini image API.

Usage:
  python3 gen_art.py probe            # generate 3 style-probe images
  python3 gen_art.py all              # generate every missing icon
  python3 gen_art.py only <key> ...   # (re)generate specific keys
Key: GEMINI_API_KEY env var, or GEMINI_API_KEY=... line in sett-v2/.env
"""
import base64, json, os, sys, time, urllib.request, urllib.error

MODEL = os.environ.get("ART_MODEL", "gemini-2.5-flash-image")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "exercise-art")
os.makedirs(OUT, exist_ok=True)

def api_key():
    k = os.environ.get("GEMINI_API_KEY")
    if k:
        return k.strip()
    env = "/Users/borja/Projects/sett-v2/.env"
    if os.path.exists(env):
        for line in open(env):
            if line.strip().startswith("GEMINI_API_KEY="):
                return line.strip().split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit("GEMINI_API_KEY not found (env var or sett-v2/.env)")

# One locked style block so all 58 icons read as one set. Original character —
# evokes the vibe without naming protected IP.
STYLE = (
    "Square 1:1 digital illustration. A single stylized anime warrior with dramatic "
    "spiky golden hair and a fierce expression, drawn in bold 90s martial-arts anime "
    "style: thick clean linework, cel shading, dynamic pose, glowing golden-and-cyan "
    "ki aura with crackling energy sparks. The very dark navy background (#0a0d12) "
    "must FILL THE ENTIRE CANVAS edge to edge — absolutely no white margins, no "
    "rounded-rectangle app-icon frame, no border, no matte, no drop shadow around a "
    "tile. Full-bleed artwork only. The character is rim-lit by their own aura, "
    "centered, filling most of the frame, with a bold readable silhouette that stays "
    "clear at small icon size. No text, no watermark, no background scenery. "
    "Same recurring character across a whole icon set: muscular male warrior, golden "
    "spiky hair, dark blue-black training suit with cyan accents. The warrior is "
)

SCENES = {
    # chest
    "flatBenchPress": "lying flat on a bench, pressing a heavy loaded barbell straight up at lockout, plates prominent",
    "inclineBenchPress": "lying on a steeply inclined bench, pressing a loaded barbell up and slightly forward",
    "declineBenchPress": "lying on a decline bench with feet hooked high, pressing a loaded barbell above the chest",
    "chestFly": "lying on a flat bench sweeping two dumbbells together in a wide hugging arc above the chest",
    "hexPress": "lying on a bench pressing two dumbbells squeezed together over the chest",
    "chestPress": "seated at a chest press machine driving both handles forward explosively",
    "pullAround": "standing, pulling a low cable across the body in a rising arc, cable taut behind",
    "pushUps": "mid push-up in a rigid plank, palms on the ground, aura flaring along the back",
    # triceps
    "dips": "suspended between parallel bars at full lockout, legs tucked, triceps flexed",
    "tricepPushdown": "standing at a high cable, pressing the bar down to the thighs with elbows pinned",
    "skullCrusher": "lying on a bench lowering an EZ-bar toward the forehead, forearms hinged",
    "tricepExtension": "standing, both arms overhead extending a single dumbbell behind the head",
    "frenchPress": "seated, extending a dumbbell overhead with both hands, elbows tight",
    # biceps
    "bicepCurl": "standing, curling a heavy dumbbell to shoulder height with a clenched fist, bicep bulging",
    "inclineBicepCurl": "reclined on an incline bench curling two dumbbells from a deep stretch",
    "hammerBicepCurl": "standing, curling two dumbbells with neutral hammer grip, forearms vertical",
    "preacherCurl": "seated at a preacher bench, upper arms on the pad, curling an EZ-bar up",
    "concentrationCurl": "seated, elbow braced inside the knee, curling a dumbbell with total focus",
    # shoulders
    "lateralRaise": "standing, raising two dumbbells straight out to the sides in a perfect T",
    "shoulderPress": "standing, pressing a loaded barbell overhead at lockout, aura erupting upward",
    "facePulls": "standing, pulling a rope cable attachment toward the face, elbows flared high",
    "rearDeltFly": "hinged forward, sweeping two dumbbells out wide behind like spreading wings",
    "frontRaise": "standing, raising a dumbbell straight out in front to shoulder height",
    "shrugs": "standing, shrugging two very heavy dumbbells, traps flexed to the ears",
    "uprightRow": "standing, pulling a barbell vertically up the torso to chin height, elbows high",
    # back
    "latPulldown": "seated at a lat pulldown machine, pulling the wide bar down to the collarbone",
    "latPullover": "standing at a high cable, sweeping straight arms from overhead down to the thighs",
    "bentOverRow": "hinged flat-backed, rowing a heavy loaded barbell into the waist",
    "pullUp": "chin over a pull-up bar mid-rep, back flared wide, legs tucked",
    "row": "seated at a cable row, pulling the handle into the stomach, chest proud",
    "deadlift": "gripping a huge loaded barbell at mid-shin in a deep hinge, about to explode upward",
    "backExtension": "on a back extension bench, torso rising to a proud arch, arms crossed",
    # legs
    "squat": "deep in a heavy barbell back squat, bar loaded with big plates, thighs parallel",
    "hackSquat": "reclined on a hack squat sled, driving up through the platform",
    "bulgarianSplitSquat": "rear foot elevated on a bench, deep in a split squat holding dumbbells",
    "legExtension": "seated on a leg extension machine, kicking the pad to full lockout",
    "legCurl": "lying prone on a leg curl machine, heels curling the pad toward the glutes",
    "hipThrust": "shoulders on a bench, driving a barbell up with the hips in a powerful bridge",
    "sumoDeadlift": "pulling a loaded barbell in an extremely wide sumo stance, knees out",
    "romanianDeadlift": "hinged with near-straight legs, barbell sliding down the thighs, hamstrings loaded",
    "standingCalfRaises": "standing on a raised block on tiptoes, holding a dumbbell, calves carved",
    "seatedCalfRaises": "seated with a weight pad on the knees, heels raised high",
    "lunges": "mid walking lunge holding two dumbbells, rear knee kissing the ground",
    "legPress": "seated in a leg press machine, pressing a heavily loaded sled with both feet",
    "kickbacks": "leaning on a frame, driving one leg straight back against a cable, glute flexed",
    # core
    "crunches": "lying on the ground mid-crunch, abs carved and glowing",
    "plank": "in a rigid forearm plank, whole body a straight beam, aura steady",
    "hangingLegRaise": "hanging from a bar, raising both legs to an L-sit",
    "russianTwist": "seated in a V, twisting the torso with hands clasped, feet hovering",
    "farmersCarry": "walking upright carrying two massive dumbbells at the sides, veins popping",
    # muscle-group emblems (custom-exercise defaults) — flex poses, no equipment
    "muscle_chest": "striking a most-muscular crab pose, chest cramping with power",
    "muscle_triceps": "flexing one arm locked straight overhead, triceps horseshoe carved",
    "muscle_biceps": "hitting a front double biceps pose, both arms flexed hard",
    "muscle_shoulders": "arms spread dead straight in an iron-cross T, delts capped",
    "muscle_back": "hitting a rear lat spread, back flared impossibly wide",
    "muscle_legs": "in a rooted horse stance, quads carved, fists at the hips",
    "muscle_core": "in a rigid plank, core glowing through the suit",
    "muscle_other": "in a power-up stance, fists clenched at the sides, aura detonating upward",
}

def generate(key, scene, api, retries=3):
    prompt = STYLE + scene + "."
    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }).encode()
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
    for attempt in range(retries):
        req = urllib.request.Request(url, data=body, headers={
            "Content-Type": "application/json", "x-goog-api-key": api})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = json.load(resp)
            for part in data["candidates"][0]["content"]["parts"]:
                blob = part.get("inlineData") or part.get("inline_data")
                if blob:
                    raw = base64.b64decode(blob["data"])
                    open(os.path.join(OUT, f"{key}.png"), "wb").write(raw)
                    return True
            print(f"  {key}: no image part in response", flush=True)
        except urllib.error.HTTPError as e:
            msg = e.read()[:200]
            print(f"  {key}: HTTP {e.code} {msg}", flush=True)
            if e.code == 429:
                time.sleep(20 * (attempt + 1))
                continue
        except Exception as e:  # noqa
            print(f"  {key}: {e}", flush=True)
        time.sleep(3)
    return False

def main():
    api = api_key()
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    if mode == "probe":
        keys = ["squat", "bicepCurl", "muscle_back"]
    elif mode == "only":
        keys = sys.argv[2:]
    else:
        keys = [k for k in SCENES if not os.path.exists(os.path.join(OUT, f"{k}.png"))]
    print(f"generating {len(keys)} icons with {MODEL}")
    ok = fail = 0
    for i, key in enumerate(keys):
        good = generate(key, SCENES[key], api)
        ok += good; fail += (not good)
        print(f"[{i+1}/{len(keys)}] {key}: {'ok' if good else 'FAILED'}", flush=True)
        time.sleep(1.2)   # be polite to rate limits
    print(f"done: {ok} ok, {fail} failed")

if __name__ == "__main__":
    main()
