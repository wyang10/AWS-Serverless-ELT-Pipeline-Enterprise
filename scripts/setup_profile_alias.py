#!/usr/bin/env python3
import argparse
import configparser
from pathlib import Path


def _write_with_mode(path: Path, cfg: configparser.RawConfigParser) -> None:
    mode = path.stat().st_mode if path.exists() else 0o600
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        cfg.write(f)
    try:
        path.chmod(mode)
    except Exception:
        pass


def main() -> int:
    parser = argparse.ArgumentParser(description="Create/update a local AWS profile alias without printing secrets.")
    parser.add_argument("--profile", required=True, help="Target profile name (e.g. audrey-tf)")
    parser.add_argument("--from", dest="source", default="default", help="Source profile in ~/.aws/credentials")
    parser.add_argument("--region", default="us-east-2")
    parser.add_argument("--output", default="json")
    args = parser.parse_args()

    cred_path = Path.home() / ".aws" / "credentials"
    config_path = Path.home() / ".aws" / "config"

    cred = configparser.RawConfigParser()
    cred.read(cred_path)
    if not cred.has_section(args.source):
        raise SystemExit(f"Missing [{args.source}] in {cred_path}")

    if not cred.has_section(args.profile):
        cred.add_section(args.profile)

    for key in ("aws_access_key_id", "aws_secret_access_key", "aws_session_token"):
        if cred.has_option(args.source, key):
            cred.set(args.profile, key, cred.get(args.source, key))

    _write_with_mode(cred_path, cred)

    cfg = configparser.RawConfigParser()
    cfg.read(config_path)
    section = f"profile {args.profile}"
    if not cfg.has_section(section):
        cfg.add_section(section)
    cfg.set(section, "region", args.region)
    cfg.set(section, "output", args.output)
    _write_with_mode(config_path, cfg)

    print(f"OK: profile '{args.profile}' configured (region={args.region}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
