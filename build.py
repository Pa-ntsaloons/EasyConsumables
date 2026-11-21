"""Build the release zip: dist/EasyConsumables-<version>.zip

Packs every file listed in EasyConsumables.toc plus README, CHANGELOG and LICENSE into an
EasyConsumables/ folder, so the zip always matches what the game loads.

Usage:  python build.py              build the zip
        python build.py --install    also copy the files into the game's AddOns folder
"""
import pathlib
import re
import shutil
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent
NAME = "EasyConsumables"
EXTRA = ["README.md", "CHANGELOG.md", "LICENSE"]
GAME_ADDONS = pathlib.Path(r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns")


def toc_files():
    toc = (ROOT / f"{NAME}.toc").read_text(encoding="utf-8")
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    files = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("#")]
    return version, [f"{NAME}.toc"] + files + EXTRA


def check(files):
    missing = [f for f in files if not (ROOT / f).is_file()]
    if missing:
        sys.exit(f"missing files: {', '.join(missing)}")
    # A real line break inside a "..." string stops the game loading the file; catch it here.
    for f in files:
        if f.endswith(".lua"):
            for n, line in enumerate((ROOT / f).read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("--", 1)[0].replace('\\"', "")
                if code.count('"') % 2:
                    sys.exit(f"{f}:{n}: unbalanced quote: {line.strip()}")


def main():
    version, files = toc_files()
    check(files)
    out = ROOT / "dist" / f"{NAME}-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            z.write(ROOT / f, f"{NAME}/{f}")
    print(f"built {out.relative_to(ROOT)} ({len(files)} files)")

    if "--install" in sys.argv:
        dest = GAME_ADDONS / NAME
        dest.mkdir(parents=True, exist_ok=True)
        for f in files:
            shutil.copy2(ROOT / f, dest / f)
        # Remove code files the .toc no longer lists (e.g. after a refactor).
        for old in dest.glob("*.lua"):
            if old.name not in files:
                old.unlink()
                print(f"removed old {old.name}")
        print(f"copied to {dest}")


if __name__ == "__main__":
    main()
