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
OUT = os.environ.get("ART_OUT") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "exercise-art")
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

# One locked style block so all 58 icons read as one set. v2: an ORIGINAL abstract
# energy-silhouette — faceless, no costume, no hair color — so it cannot read as any
# franchise character, with the working muscles blazing from within (the emphasis).
STYLE = (
    "Square 1:1 digital illustration, full-bleed on a very dark navy background "
    "(#0a0d12) that fills the entire canvas edge to edge — no white margins, no "
    "rounded-icon frame, no border, no matte. An ORIGINAL abstract ENERGY WARRIOR: "
    "a completely FACELESS dark humanoid silhouette — no facial features, no eyes, "
    "no mouth, no skin tone, no clothing details — its head crowned by an abstract "
    "upswept crest of pure flame-like energy. The figure is matte near-black, "
    "rim-lit in electric cyan, wrapped in a crackling cyan-white aura with lightning "
    "arcs. COLOR LOCK: the flame crest, rim light and aura are ALWAYS electric "
    "CYAN-WHITE — never gold, yellow or orange. KEY LIGHTING RULE: ONLY the exact "
    "PRIMARY WORKING MUSCLES named for this movement blaze from WITHIN the silhouette "
    "in molten gold, like magma glowing through cracked armor — the hottest brightest "
    "region of the image. Be ANATOMICALLY PRECISE: light ONLY that named muscle group "
    "and keep every other body region dark near-black; NEVER let the gold leak onto "
    "the abs/core unless the core is the named target. So the target muscle group is "
    "unmistakable at a glance. Bold heroic energy: thick simple shapes, cel-shaded "
    "glow, dynamic pose, bold readable silhouette that stays clear at small icon "
    "size. Completely original design — must NOT resemble any existing anime, manga, "
    "or video-game character or franchise. Centered, filling most of the frame. "
    "No text, no watermark, no background scenery. The warrior is "
)

SCENES = {
    # chest
    "flatBenchPress": "lying flat on a bench, pressing a heavy loaded barbell straight up at lockout, plates prominent",
    "inclineBenchPress": "lying on a steeply inclined bench, pressing a loaded barbell up and slightly forward",
    "declineBenchPress": "lying on a decline bench with feet hooked high, pressing a loaded barbell above the chest",
    "chestFly": "seated upright at a pec-deck fly machine, bringing both padded arms together in front of the chest; the PECTORAL chest muscles blaze, the core stays dark",
    "hexPress": "lying on a bench pressing two dumbbells squeezed together over the chest",
    "chestPress": "seated at a chest press machine driving both handles forward explosively",
    "pullAround": "standing, pulling a low cable across the body in a rising arc, cable taut behind",
    "pushUps": "mid push-up in a rigid plank, palms on the ground, aura flaring along the back",
    # triceps
    "dips": "suspended between parallel bars at full lockout, legs tucked, triceps flexed",
    "tricepPushdown": "standing at a high cable, pressing the bar down to the thighs with elbows pinned",
    "skullCrusher": "lying on a bench lowering an EZ-bar toward the forehead, forearms hinged",
    "tricepExtension": "standing, both arms overhead extending a single dumbbell behind the head",
    "frenchPress": "seated on a bench, both hands cupping ONE single dumbbell held overhead, extending it up while the elbows stay tight; the TRICEPS blaze",
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
    "latPulldown": "rear three-quarter view, seated at a lat pulldown machine gripping the wide overhead bar and pulling it down behind toward the upper back; the LATS and back muscles flare wide and blaze molten gold",
    "latPullover": "standing at a high cable, sweeping straight arms from overhead down to the thighs",
    "bentOverRow": "hinged flat-backed, rowing a heavy loaded barbell into the waist",
    "pullUp": "chin over a pull-up bar mid-rep, back flared wide, legs tucked",
    "row": "seated at a cable row, pulling the handle into the stomach, chest proud",
    "deadlift": "gripping a huge loaded barbell at mid-shin in a deep hinge, about to explode upward",
    "backExtension": "on a back extension bench, torso rising to a proud arch, arms crossed",
    # legs
    "squat": "deep in a heavy barbell back squat, bar loaded with big plates, thighs parallel",
    "hackSquat": "reclined on a hack squat sled, driving up through the platform",
    "bulgarianSplitSquat": "in a deep split squat with the REAR foot resting up on top of a bench behind, front leg bent and lunging, holding a dumbbell in each hand; the front QUADRICEPS and glute blaze",
    "legExtension": "seated on a leg extension machine, kicking the pad to full lockout",
    "legCurl": "lying prone on a leg curl machine, heels curling the pad toward the glutes",
    "hipThrust": "upper back braced against a bench, feet planted, a loaded barbell resting ACROSS the HIPS/lap, driving the hips up into a flat bridge; the GLUTES blaze",
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
    # muscle-group emblems (custom-exercise defaults) — flex poses, no equipment.
    # Each names its glow target explicitly: ONLY that region burns molten gold.
    "muscle_chest": "facing the viewer, arms pressed together low in a most-muscular pose; ONLY the two big PECTORAL chest plates across the UPPER torso blaze molten gold — the abs and core stay completely dark",
    "muscle_triceps": "rear three-quarter view, one arm bent and locked overhead; ONLY the TRICEPS horseshoe on the BACK of that upper arm (between shoulder and elbow) blazes molten gold — the forearm, shoulder and rest of the body stay dark",
    "muscle_biceps": "a single powerful arm flexed and curled — upper arm angled, fist up near the shoulder. The BICEP is the big round peak that balls up on the upper arm at peak contraction; ONLY that bicep peak blazes molten gold. The forearm and fist stay dark. The other arm rests at the side",
    "muscle_shoulders": "arms spread dead straight out to the sides in a T; ONLY the two round DELTOID caps on top of the shoulders blaze molten gold — the chest, arms and core stay completely dark",
    "muscle_back": "seen ENTIRELY FROM BEHIND — only the back of the head crest visible, absolutely no face — hitting a rear lat spread, elbows flared; ONLY the LATS and upper back blaze molten gold in a wide V",
    "muscle_legs": "rooted in a wide stance, fists at the hips; the ENTIRE QUADRICEPS on the front of BOTH thighs (from hip to knee) blaze molten gold — the torso and core stay dark",
    "muscle_core": "standing braced, fists clenched at the sides; ONLY the six-pack ABDOMINAL grid on the belly blazes molten gold, everything else dark",
    "muscle_other": "in a rising power-up stance, aura detonating upward; the WHOLE BODY is veined evenly with molten-gold energy cracks",
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
