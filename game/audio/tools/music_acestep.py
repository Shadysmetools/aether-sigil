"""Render the Aether Sigil score with ACE-Step v1-3.5B (Apache-2.0 code + weights), GPU-polite.

Run with the ACE-Step venv's python:
  "<ACE-Step>/.venv/Scripts/python.exe" music_acestep.py <work_dir> [--checkpoint <dir>] [--only T01_explore,...]

Shares the GPU with a ComfyUI batch at 127.0.0.1:8188: before loading the model and before EVERY
clip it checks the ComfyUI queue (queue_running + queue_pending must be empty) and free VRAM;
if ComfyUI has work, the process exits with code 3 so its VRAM is released at once (run it
from a wait loop, see music_gpu_wait.sh). Renders already on disk are skipped, so it resumes.
Instrumental only ("[inst]" lyrics + "instrumental, no vocals" tags). Prompts describe original
styles only - no artist, composer, game or franchise names.
"""
import json
import subprocess
import sys
import time
import urllib.request
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from music_build import ROLE_WORDS, TAKES, TOWERS, track_ids  # noqa: E402

TAKE_WORDS = {
    "a": "steady marching rhythm, heroic, 120 bpm",
    "b": "syncopated driving rhythm, brighter, 132 bpm",
    "c": "relentless fast rhythm, darker, high tension, 145 bpm",
}
DURATION = 104.0
MIN_FREE_MB = 6500


def comfy_busy():
    try:
        with urllib.request.urlopen("http://127.0.0.1:8188/queue", timeout=5) as r:
            q = json.loads(r.read())
        return bool(q.get("queue_running") or q.get("queue_pending"))
    except Exception:
        return False  # ComfyUI not running at all = not busy


def free_mb():
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=10).stdout
        return int(out.strip().splitlines()[0])
    except Exception:
        return 0


def gpu_free():
    return not comfy_busy() and free_mb() >= MIN_FREE_MB


def job(tid):
    if tid == "final_boss":
        style = TOWERS["12"]["prompt"] + ", " + ROLE_WORDS["final"]
    else:
        tw, role = tid[1:3], tid.split("_", 1)[1]
        style = TOWERS[tw]["prompt"]
        if role.startswith("battle_"):
            style += ", " + ROLE_WORDS["battle"] + ", " + TAKE_WORDS[role[-1]]
        else:
            style += ", " + ROLE_WORDS[role]
    seed = zlib.crc32(tid.encode()) % 2_000_000_000
    return {"prompt": "fantasy anime game soundtrack, " + style, "lyrics": "[inst]", "seed": seed,
            "duration": DURATION}


def main():
    work = Path(sys.argv[1])
    args = sys.argv[2:]
    ckpt = args[args.index("--checkpoint") + 1] if "--checkpoint" in args else ""
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None
    out = work / "gen"
    out.mkdir(parents=True, exist_ok=True)
    todo = [t for t in track_ids() if (only is None or t in only) and not (out / f"{t}.wav").exists()]
    if not todo:
        print("ALL_DONE")
        return 0
    if not gpu_free():
        print(f"GPU_BUSY comfy={comfy_busy()} free_mb={free_mb()}")
        return 3
    from acestep.pipeline_ace_step import ACEStepPipeline
    pipe = ACEStepPipeline(checkpoint_dir=ckpt, dtype="bfloat16", torch_compile=False,
                           cpu_offload=True, overlapped_decode=True)
    for tid in todo:
        if comfy_busy():
            print("GPU_BUSY before", tid)
            return 3
        j = job(tid)
        t0 = time.time()
        pipe(format="wav", audio_duration=j["duration"], prompt=j["prompt"], lyrics=j["lyrics"],
             infer_step=60, guidance_scale=15.0, scheduler_type="euler", cfg_type="apg", omega_scale=10.0,
             manual_seeds=[j["seed"]], guidance_interval=0.5, guidance_interval_decay=0.0,
             min_guidance_scale=3.0, use_erg_tag=True, use_erg_lyric=False, use_erg_diffusion=True,
             oss_steps="", guidance_scale_text=0.0, guidance_scale_lyric=0.0,
             save_path=str(out / f"{tid}.wav"))
        (out / f"{tid}.json").write_text(json.dumps({**j, "model": "ACE-Step/ACE-Step-v1-3.5B",
                                                     "seconds": round(time.time() - t0, 1)}, indent=1))
        print(f"RENDERED {tid} in {time.time() - t0:.0f}s", flush=True)
    print("ALL_DONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
