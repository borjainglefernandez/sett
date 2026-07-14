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

# One locked style block so all 58 icons read as one set. v3: a tight CLOSE-UP framed
# on the WORKING REGION (upper vs lower body vs core) so ONE big bold subject fills the
# frame — legible at 40pt where a full-body long shot turns to mud. Faceless original
# energy-silhouette; working muscles blaze from within (the emphasis).
STYLE_BASE = (
    "Square 1:1 BOLD ICON, full-bleed on a solid very dark navy background (#0a0d12) "
    "that fills the whole canvas edge to edge. The dark navy MUST bleed into all four "
    "corners and every edge — NEVER a white or light square, NEVER a rounded-rectangle "
    "app-icon frame, NEVER a border ring or matte around the art. An ORIGINAL abstract "
    "ENERGY WARRIOR: a completely FACELESS "
    "matte near-black form — no facial features, no skin tone, no clothing — rim-lit in "
    "electric cyan and wrapped in a crackling cyan-white aura. COLOR LOCK: the rim light "
    "and aura are ALWAYS electric CYAN-WHITE, never gold, yellow or orange. "
    "This is an ICON, NOT a scene: ONE single big bold subject, thick simple shapes, "
    "cel-shaded glow, extreme high contrast (bright form on near-black). It MUST stay "
    "instantly recognizable when shrunk to a 40x40 pixel thumbnail — if a detail would "
    "disappear at 40px, do not draw it. Absolutely NO text, NO watermark, NO background "
    "scenery, NO floor, and NO tiny distant full-body long shot. Completely original "
    "design — must NOT resemble any existing anime, manga or video-game character. "
)

# Per-region framing: crop the composition to the half of the body that's working, so it
# fills the frame. The equipment in the cropped-out half is simply not shown.
REGION_CROP = {
    "upper": (
        "COMPOSITION: an extreme CLOSE-UP framed on the UPPER BODY — the chest, shoulders, "
        "upper back and arms FILL the entire frame, cropped around the waist so the legs are "
        "NOT shown. The torso and arms performing the movement fill the frame. "
    ),
    "lower": (
        "COMPOSITION: an extreme CLOSE-UP framed on the LOWER BODY — the hips, glutes and "
        "powerful thighs down past the knees FILL the entire frame, cropped around the waist "
        "so the head, chest and arms are NOT shown. The driving legs performing the movement "
        "fill the frame. "
    ),
    "core": (
        "COMPOSITION: an extreme CLOSE-UP framed on the TORSO and MIDSECTION — the abdominal "
        "core fills the entire frame, cropped above the chest and below the hips. "
    ),
    "full": (
        "COMPOSITION: the warrior fills the entire frame in a bold heroic power stance. "
    ),
}

STYLE_TAIL = (
    "KEY LIGHTING: ONLY the primary working muscles for this movement blaze from WITHIN the "
    "form in molten gold, like magma through cracked armor — the single hottest brightest "
    "region of the image; keep every other area dark near-black and NEVER let the gold leak "
    "onto the core unless the core is the target. "
)
# Equipment clause is conditional: bodyweight movements must show NO implement.
EQUIP_WEIGHTED = (
    "Show exactly ONE heavy, unmistakable implement (barbell / dumbbell / handle / machine pad), "
    "thicker than any limb, and crop everything else out. "
)
EQUIP_BODYWEIGHT = (
    "This is a BODYWEIGHT movement — show NO equipment, NO barbell, NO dumbbell at all, just the "
    "bare working muscles of the body. "
)
BODYWEIGHT = {
    "pushUps", "dips", "pullUp", "crunches", "plank", "hangingLegRaise", "russianTwist",
    "backExtension", "muscle_chest", "muscle_triceps", "muscle_biceps", "muscle_shoulders",
    "muscle_back", "muscle_legs", "muscle_core", "muscle_other",
}
TAIL_END = "The movement is: "

# Which body-half each icon frames — follows the catalog muscle group.
REGION = {}
for _k in ["flatBenchPress", "inclineBenchPress", "declineBenchPress", "chestFly", "hexPress",
           "chestPress", "pullAround", "pushUps", "dips", "tricepPushdown", "skullCrusher",
           "tricepExtension", "frenchPress", "bicepCurl", "inclineBicepCurl", "hammerBicepCurl",
           "preacherCurl", "concentrationCurl", "lateralRaise", "shoulderPress", "facePulls",
           "rearDeltFly", "frontRaise", "shrugs", "uprightRow", "latPulldown", "latPullover",
           "bentOverRow", "pullUp", "row", "deadlift", "backExtension",
           "muscle_chest", "muscle_triceps", "muscle_biceps", "muscle_shoulders", "muscle_back"]:
    REGION[_k] = "upper"
for _k in ["squat", "hackSquat", "bulgarianSplitSquat", "legExtension", "legCurl", "hipThrust",
           "sumoDeadlift", "romanianDeadlift", "standingCalfRaises", "seatedCalfRaises", "lunges",
           "legPress", "kickbacks", "muscle_legs"]:
    REGION[_k] = "lower"
for _k in ["crunches", "plank", "hangingLegRaise", "russianTwist", "farmersCarry", "muscle_core"]:
    REGION[_k] = "core"
REGION["muscle_other"] = "full"

# Camera/composition overrides for movements that are NOT a frontal standing close-up.
# These REPLACE the region crop so lying / hanging / prone poses can't read as standing —
# the #1 accuracy failure (a lying bench press rendering as a standing overhead press).
_LYING = ("COMPOSITION: a SIDE-PROFILE view of the warrior LYING DOWN HORIZONTALLY on a bench, "
          "the reclining body stretched across and filling the frame. The body is unmistakably "
          "HORIZONTAL — NOT standing, NOT seated upright. Show the bench line beneath the back. ")
_PRONE = ("COMPOSITION: a SIDE view of the warrior lying FACE-DOWN (prone) on a bench/pad, the "
          "horizontal body filling the frame — clearly prone and horizontal, never standing. ")
_HANG = ("COMPOSITION: the warrior HANGING vertically from a HIGH bar at the very top of the frame, "
         "both arms straight up overhead gripping the bar, the suspended body filling the frame below. ")
_BRIDGE = ("COMPOSITION: a SIDE view of the warrior HORIZONTAL in a hip bridge — shoulders on a bench, "
           "hips lifted into a flat tabletop, the body horizontal and filling the frame. ")
_PLANK = ("COMPOSITION: a SIDE view of the warrior HORIZONTAL in a forearm plank, the body one rigid "
          "straight beam parallel to the ground, forearms flat down, filling the frame. ")
POSE_OVERRIDE = {
    "flatBenchPress": _LYING, "inclineBenchPress": _LYING, "declineBenchPress": _LYING,
    "hexPress": _LYING, "skullCrusher": _LYING,
    "legCurl": _PRONE, "backExtension": _PRONE,
    "hipThrust": _BRIDGE,
    "pullUp": _HANG, "hangingLegRaise": _HANG,
    "plank": _PLANK,
}

SCENES = {
    # chest
    "flatBenchPress": "lying flat on their back on the bench, pressing a loaded barbell straight up above the mid-chest to lockout",
    "inclineBenchPress": "reclined back on a clearly inclined bench (about 45 degrees), pressing a loaded barbell up and back over the upper chest",
    "declineBenchPress": "lying head-DOWN on a decline bench with the feet hooked at the raised high end, pressing a loaded barbell above the chest",
    "chestFly": "seated at a pec-deck fly machine, both padded arms sweeping together in front of the chest with the elbows flared out wide; the PECTORAL chest muscles blaze, the core stays dark",
    "hexPress": "lying flat on their back on the bench, pressing two dumbbells squeezed together and TOUCHING directly above the mid-chest, arms squeezing inward",
    "chestPress": "seated at a chest-press machine, driving both handles HORIZONTALLY forward away from the chest to full arm extension",
    "pullAround": "standing, sweeping one nearly-straight arm in a wide cross-body arc from a low pulley, the cable taut; the chest lights up",
    "pushUps": "mid push-up in a rigid plank, palms on the ground, aura flaring along the back",
    # triceps
    "dips": "suspended between parallel bars at full lockout, legs tucked, triceps flexed",
    "tricepPushdown": "standing at a high cable that descends from the top of the frame to a straight bar, pressing it down to the thighs with the elbows pinned tight to the ribs",
    "skullCrusher": "lying flat on their back on the bench, lowering an EZ-bar toward the forehead with the upper arms fixed vertical and the elbows pointing up",
    "tricepExtension": "standing, both hands cupping ONE single dumbbell held low BEHIND the head with the elbows deeply BENT and pointing straight UP (mid-stretch, NOT locked out); ONLY the TRICEPS on the back of the upper arms blaze — this is an extension, not an overhead press",
    "frenchPress": "seated on a bench, both hands cupping ONE single dumbbell held vertically behind the head, elbows tight and pointing up, extending it upward; the TRICEPS blaze",
    # biceps
    "bicepCurl": "standing, curling a heavy dumbbell to shoulder height with a clenched fist, bicep bulging",
    "inclineBicepCurl": "reclined on an incline bench curling two dumbbells from a deep stretch",
    "hammerBicepCurl": "standing, curling two dumbbells with neutral hammer grip, forearms vertical",
    "preacherCurl": "seated at a preacher bench, upper arms on the pad, curling an EZ-bar up",
    "concentrationCurl": "seated and hunched forward, the working elbow braced against the inner thigh, curling a single dumbbell up; the bicep blazes",
    # shoulders
    "lateralRaise": "standing, raising two dumbbells straight out to the sides in a perfect T",
    "shoulderPress": "standing, pressing a loaded barbell overhead at lockout, aura erupting upward",
    "facePulls": "standing, pulling a rope cable attachment toward the face, elbows flared high",
    "rearDeltFly": "torso hinged forward about 90 degrees at the hips with a flat back, sweeping two dumbbells up and out to the sides like spreading wings; the REAR delts and upper back blaze",
    "frontRaise": "SIDE view, standing, the working arm fully STRAIGHT (elbow locked) raising a dumbbell directly out in FRONT to shoulder height, dumbbell at eye level, arm parallel to the floor; the SAME front delt doing the lift blazes — the other arm rests at the side",
    "shrugs": "standing with both arms hanging straight DOWN at the sides holding heavy dumbbells, the shoulders shrugged hard up toward the ears; the TRAPS (neck-to-shoulder ridge) blaze",
    "uprightRow": "standing, pulling a barbell with a narrow grip vertically up the FRONT of the torso to chin height, the elbows flared high above the wrists; the traps and side delts blaze",
    # back
    "latPulldown": "rear three-quarter view, seated at a lat pulldown machine gripping the wide overhead bar and pulling it down behind toward the upper back; the LATS and back muscles flare wide and blaze molten gold",
    "latPullover": "standing under a high cable/pulley above, sweeping straight arms in an arc from overhead down toward the thighs; the LATS on the sides of the back blaze",
    "bentOverRow": "SIDE view, torso hinged sharply forward to nearly parallel with the floor (flat back), knees soft, actively pulling a loaded barbell UP off arm's length INTO the waist with the elbows raised high behind the back; the mid-back and LATS blaze — NOT standing upright",
    "pullUp": "gripping a high overhead bar with the chin pulled ABOVE the bar, both arms overhead and bent, the body suspended below; the LATS and upper back blaze",
    "row": "SIDE view, seated at a cable-row station with a visible pulley stack in front, leaning back slightly and pulling a single handle horizontally INTO the stomach with the elbows driving straight back past the ribs; the mid-back and LATS blaze (NOT the abs) — NOT a standing barbell hold",
    "deadlift": "gripping a huge loaded barbell at mid-shin in a deep hinge, about to explode upward",
    "backExtension": "lying face-DOWN prone on a 45-degree hyperextension bench, hips anchored on the pad, the torso rising into a proud arch; the lower back and glutes blaze",
    # legs
    "squat": "deep in a heavy barbell back squat, bar loaded with big plates, thighs parallel",
    "hackSquat": "on an angled hack-squat sled with the shoulder pads on top and the feet planted on the platform, driving up; the quads blaze",
    "bulgarianSplitSquat": "a side-view split stance, ONE leg forward and bent lunging deep while the REAR foot is propped up on top of a bench behind, holding a dumbbell in each hand; ONLY the FRONT quad and glute blaze",
    "legExtension": "seated on a leg extension machine, kicking the pad to full lockout",
    "legCurl": "lying face-DOWN flat prone on a leg-curl bench, the heels hooked UNDER the ankle pad and curling up toward the glutes; the hamstrings blaze",
    "hipThrust": "horizontal, the upper back braced on the edge of a bench and the hips bridged UP into a flat tabletop, a loaded barbell resting ACROSS the hips; the GLUTES blaze",
    "sumoDeadlift": "an extremely wide sumo stance with the knees flared out, both hands gripping the barbell INSIDE the knees, pulling up; the quads and glutes blaze",
    "romanianDeadlift": "torso hinged sharply forward at the hips with near-straight legs, the barbell sliding down the thighs; the HAMSTRINGS on the BACK of the thighs blaze",
    "standingCalfRaises": "standing on a raised block with both heels raised HIGH onto the balls of the feet on tiptoe (an obvious gap under the heels), holding a dumbbell; the calves blaze",
    "seatedCalfRaises": "side view, seated with a weight pad clamped on the knees and the heels lifting HIGH off a foot block; the calves blaze",
    "lunges": "mid walking lunge holding two dumbbells, rear knee kissing the ground",
    "legPress": "seated in a leg press machine, pressing a heavily loaded sled with both feet",
    "kickbacks": "leaning forward on a frame, driving ONE leg straight back against an ankle-cuff cable (no hand weights); the GLUTE and hamstring blaze",
    # core
    "crunches": "a tight close-up of the torso curled up in a crunch, hands behind the head, the six-pack abdominal core carved and blazing, filling the frame",
    "plank": "holding a forearm plank, the whole body a rigid straight beam parallel to the ground with the forearms flat down; the core blazes",
    "hangingLegRaise": "the torso extended down from the overhead bar and the legs raised to an L-sit; the lower abs blaze",
    "russianTwist": "NOT cross-legged, NOT meditating — reclined back in a V-sit with the knees bent and BOTH feet LIFTED off the floor, the torso rotated hard to ONE side with both hands clasped together and swung down to that hip; the obliques and core blaze",
    "farmersCarry": "walking upright carrying two massive dumbbells at the sides, veins popping",
    # muscle-group emblems (custom-exercise defaults) — flex poses, no equipment.
    # Each names its glow target explicitly: ONLY that region burns molten gold.
    "muscle_chest": "facing the viewer, arms pressed together low in a most-muscular pose; ONLY the two big PECTORAL chest plates across the UPPER torso blaze molten gold — the abs and core stay completely dark",
    "muscle_triceps": "a rear three-quarter view with the BACK of the upper arm facing the camera and the arm locked out overhead; ONLY the TRICEPS horseshoe on the BACK of that upper arm blazes molten gold — the forearm, shoulder and rest of the body stay dark",
    "muscle_biceps": "a single arm flexed in a biceps pose, the forearm vertical and fist by the head; ONLY the round BICEP muscle BELLY on the front of the UPPER arm (between shoulder and elbow) balls up and blazes molten gold — the FOREARM, the fist and the elbow crook all stay completely DARK; the other arm rests at the side",
    "muscle_shoulders": "arms spread dead straight out to the sides in a T; ONLY the two round DELTOID caps at the very OUTER points of the shoulders blaze molten gold — the chest, arms, neck and traps stay dark",
    "muscle_back": "seen ENTIRELY FROM BEHIND — no face — hitting a rear lat spread with the two LATS flaring WIDE to the sides in a big V; ONLY the outer lat wings blaze molten gold, not the central spine",
    "muscle_legs": "rooted in a wide stance, fists at the hips; the ENTIRE QUADRICEPS on the front of BOTH thighs (from hip to knee) blaze molten gold — the torso and core stay dark",
    "muscle_core": "standing braced, fists clenched at the sides; ONLY the six-pack ABDOMINAL grid on the belly blazes molten gold, everything else dark",
    "muscle_other": "in a rising power-up stance, aura detonating upward; the WHOLE BODY is veined evenly with molten-gold energy cracks",
}

def build_prompt(key, scene):
    comp = POSE_OVERRIDE.get(key) or REGION_CROP[REGION.get(key, "full")]
    equip = EQUIP_BODYWEIGHT if key in BODYWEIGHT else EQUIP_WEIGHTED
    return STYLE_BASE + comp + STYLE_TAIL + equip + TAIL_END + scene + "."

def generate(key, scene, api, retries=3):
    prompt = build_prompt(key, scene)
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
        keys = ["flatBenchPress", "bicepCurl", "squat", "deadlift", "crunches"]
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
