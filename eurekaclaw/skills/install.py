import subprocess
import requests
import os
import eurekaclaw
from eurekaclaw.types import skills
from eurekaclaw.utils import copy_file, copy_directory
import shutil
import pathlib

CLAWHUB_REGISTRY = "https://clawhub.ai/"  # base registry API URL
SEED_SKILL_REPO = "https://github.com/EurekaClaw/seed_skills.git"
SEED_SKILL_REPO_FOLDER = "seed_skills"
SEED_SKILL_FOLDER = pathlib.Path(SEED_SKILL_REPO_FOLDER) / "seedskills"

def install_from_hub(skillname: str, dest: pathlib.Path) -> None:
    """
    Check if a skill exists on ClawHub, and install it if found.

    Args:
        skillname: The skill slug to look up and install (e.g. "steipete/github")
        dest: The destination directory for the installed skill
    """
    # 1. Check if the skill exists on ClawHub
    try:
        if not os.path.exists(dest):
            os.makedirs(dest)
        parent_dir = dest.parent
        result = subprocess.run(
            ["clawhub", "install", skillname],
            check=True,
            text=True,
            cwd=parent_dir,
            # stdout="/dev"
        )
        # print(f"Successfully installed '{skillname}'.")
        return True
    
    except FileNotFoundError:
        return False  # clawhub CLI not found, skip hub installation
    
    except subprocess.CalledProcessError as e:
        # print(f"Error installing '{skillname}': {e.stderr}")
        return False  # installation failed, skill may not exist or other error


def install_seed_skills(dest: pathlib.Path) -> None:
    """
    Install the seed skills from the SeedSkills repository on GitHub.
    """
    try:
        if not os.path.exists(dest):
            os.makedirs(dest)
        result = subprocess.run(
            ["git", "clone", SEED_SKILL_REPO],
            check=True,
            text=True,
            cwd=dest,
        )
        repo_path = os.path.join(dest, SEED_SKILL_FOLDER)

        for item in os.listdir(repo_path):
            if item != ".git" and os.path.isdir(os.path.join(repo_path, item)):
                src = os.path.join(repo_path, item)
                copy_directory(src, dest, overwrite=True)
        
        repo_path = os.path.join(dest, SEED_SKILL_REPO_FOLDER)
        shutil.rmtree(repo_path)

        # print("Successfully installed seed skills.")
    except subprocess.CalledProcessError as e:
        print(f"Error installing seed skills: {e.stderr}")


if __name__ == "__main__":
    eurekaclaw_dir = pathlib.Path.home() / ".eurekaclaw" / "skills"
    install_from_hub("self-improving-agent", eurekaclaw_dir)
    install_seed_skills(eurekaclaw_dir)