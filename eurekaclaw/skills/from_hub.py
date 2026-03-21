import subprocess
import requests
import os
import eurekaclaw
from eurekaclaw.types import skills
from eurekaclaw.utils import copy_file
import shutil

CLAWHUB_REGISTRY = "https://clawhub.ai/"  # base registry API URL

def install_from_hub(skillname: str, dest: str) -> None:
    """
    Check if a skill exists on ClawHub, and install it if found.

    Args:
        skillname: The skill slug to look up and install (e.g. "steipete/github")
        dest: The destination directory for the installed skill
    """
    # 1. Check if the skill exists on ClawHub
    try:
        skills_dir = os.path.join(os.path.dirname(eurekaclaw.__file__), "skills")
        result = subprocess.run(
            ["clawhub", "install", skillname],
            check=True,
            text=True,
            cwd=skills_dir,
            # stdout="/dev"
        )
        print(f"Successfully installed '{skillname}'.")
        # remove the folder skills_dir / .clawhub/
        clawhub_dir = os.path.join(skills_dir, ".clawhub")
        if os.path.exists(clawhub_dir):
            shutil.rmtree(clawhub_dir)
    
        src = os.path.join(skills_dir, "skills", skillname)
        dst = os.path.join(dest, skillname)
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(src, dst)

        if os.path.exists(src):
            shutil.rmtree(src)

        return True
    except FileNotFoundError:
        return False  # clawhub CLI not found, skip hub installation
    
    except subprocess.CalledProcessError as e:
        # print(f"Error installing '{skillname}': {e.stderr}")
        return False  # installation failed, skill may not exist or other error
    